import azure.functions as func
import logging
import os
import json
import time
import random
import uuid
from typing import Optional, Tuple

import requests
from azure.identity import DefaultAzureCredential
from azure.core.exceptions import ClientAuthenticationError

# Try to set up OpenTelemetry / Application Insights if azure-monitor-opentelemetry is installed
try:
    from azure.monitor.opentelemetry import configure_azure_monitor
    configure_azure_monitor()  # Uses connection string from APPLICATIONINSIGHTS_CONNECTION_STRING if set
    logging.getLogger().info("Azure Monitor OpenTelemetry configured.")
except Exception as _telemetry_err:  # broad to avoid failing function if not installed or misconfigured
    logging.getLogger().warning(f"Azure Monitor OpenTelemetry not fully configured: {_telemetry_err}")

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


def _get_access_token(scope: str) -> Optional[str]:
    """Acquire an access token using DefaultAzureCredential for the given scope.
    Returns None if resource key authentication should be used instead.
    """
    # If API key is configured, skip token acquisition
    if os.getenv("CONTENT_UNDERSTANDING_API_KEY"):
        return None
    
    credential = DefaultAzureCredential()
    try:
        token = credential.get_token(scope)
        return token.token
    except ClientAuthenticationError as e:
        logging.error(f"Authentication failed: {e}")
        raise


def _exponential_backoff_poll(result_url: str, headers: dict, max_wait_seconds: int = 600, max_retries: int = 10, correlation_id: Optional[str] = None) -> Tuple[int, dict]:
    """Poll the analyzer result endpoint using exponential backoff.
    Returns final status code and JSON body.
    """
    attempt = 0
    total_wait = 0
    base_delay = 10.0  # seconds
    while attempt < max_retries and total_wait < max_wait_seconds:
        try:
            poll_headers = dict(headers)
            if correlation_id:
                poll_headers["x-correlation-id"] = correlation_id
            resp = requests.get(result_url, headers=poll_headers, timeout=30)
        except requests.RequestException as e:
            logging.warning(f"[{correlation_id}] Polling attempt {attempt} failed due to network error: {e}")
            # Treat as transient; continue
            resp = None

        if resp is not None:
            try:
                body = resp.json()
            except ValueError:
                body = {"raw": resp.text}

            if resp.status_code == 200:
                status = body.get("status")
                if status in ("Succeeded", "Failed", "Canceled"):
                    return resp.status_code, body
            elif resp.status_code >= 400:
                # Non-retryable HTTP error from status endpoint
                return resp.status_code, body

        # Need another attempt: compute backoff (exponential + jitter)
        sleep_for = base_delay * (2 ** attempt)
        # Cap each sleep so we don't overshoot drastically
        sleep_for = min(sleep_for, 30.0)
        # Add jitter (10-30 seconds)
        sleep_for += random.uniform(10, 30)
        # Ensure we don't exceed max_wait_seconds
        if total_wait + sleep_for > max_wait_seconds:
            break
        logging.info(f"[{correlation_id}] Polling attempt {attempt} not finished, sleeping {sleep_for:.2f}s before next attempt.")
        time.sleep(sleep_for)
        total_wait += sleep_for
        attempt += 1

    return 200, {"status": "Timeout", "message": "Polling timed out before completion."}


@app.route(route="whoami", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def whoami(req: func.HttpRequest) -> func.HttpResponse:
    """Diagnostic endpoint to surface Easy Auth injected headers for troubleshooting authentication.
    Returns principal, identity provider, and raw auth headers (excluding the bearer token).
    """
    correlation_id = req.headers.get("x-correlation-id") or str(uuid.uuid4())
    # Easy Auth standard headers
    header_map = {}
    interesting = [
        "X-MS-CLIENT-PRINCIPAL-ID",
        "X-MS-CLIENT-PRINCIPAL-IDP",
        "X-MS-CLIENT-PRINCIPAL-NAME",
        "X-MS-CLIENT-PRINCIPAL",
        "X-MS-TOKEN-AAD-ID-TOKEN",
        "X-MS-TOKEN-AAD-ACCESS-TOKEN",
        "X-MS-CLIENT-IP",
        "X-MS-CLIENT-PRINCIPAL-GROUPS"
    ]
    for h in interesting:
        if h in req.headers:
            header_map[h] = req.headers[h]
    # Indicate whether Authorization header was present (do not echo token)
    auth_present = "Authorization" in req.headers
    body = {
        "correlationId": correlation_id,
        "authorizationHeaderPresent": auth_present,
        "principalHeaders": header_map,
        "note": "If principalHeaders is empty, authentication failed or Easy Auth did not inject claims."
    }
    return func.HttpResponse(json.dumps(body), status_code=200, mimetype="application/json")


@app.route(route="", methods=["POST", "GET"], auth_level=func.AuthLevel.ANONYMOUS)
def ai_content_understanding(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP trigger function acting as an enriched wrapper for analyzer operations.

    Authentication:
      - Uses CONTENT_UNDERSTANDING_API_KEY (Ocp-Apim-Subscription-Key) if set
      - Falls back to Azure AD token via DefaultAzureCredential (managed identity)

    Query/body parameters:
      - baseUrl: Upstream Content Understanding base URL (required if not set via env CONTENT_UNDERSTANDING_BASE_URL)
      - analyzerId: Analyzer identifier (default from ANALYZER_ID env or 'prebuilt-invoice')
      - api-version: Upstream API version (default '2025-05-01-preview')
      - url | data: Source content (one required)
      - poll: Always polls to completion (default true)
      - maxWaitSeconds: override total poll wait (default 600)
      - maxRetries: override max poll attempts (default 10)
      - retryAfterSeconds: override Retry-After when still running (default 30)
    """
    correlation_id = req.headers.get("x-correlation-id") or str(uuid.uuid4())
    logging.info(f"[{correlation_id}] Received content understanding request method={req.method}")

    # Extract JSON body once for shared params
    try:
        body_all = req.get_json()
    except ValueError:
        body_all = {}

    api_version = req.params.get("api-version") or body_all.get("api-version") or "2025-05-01-preview"
    base_url = req.params.get("baseUrl") or body_all.get("baseUrl") or os.getenv("CONTENT_UNDERSTANDING_BASE_URL")
    if not base_url:
        diagnostic_payload = {
            "error": "Missing baseUrl (query/body) and CONTENT_UNDERSTANDING_BASE_URL not set.",
            "correlationId": correlation_id,
            "received": {
                "query": {k: req.params.get(k) for k in req.params.keys()},
                "bodyKeys": list(body_all.keys()) if isinstance(body_all, dict) else None,
                "envHasBaseUrl": bool(os.getenv("CONTENT_UNDERSTANDING_BASE_URL"))
            }
        }
        return func.HttpResponse(json.dumps(diagnostic_payload), status_code=400, mimetype="application/json")

    analyzer_id = req.params.get("analyzerId") or body_all.get("analyzerId") or os.getenv("ANALYZER_ID") or "prebuilt-invoice"
    
    # Determine authentication method: API key takes precedence over token
    api_key = os.getenv("CONTENT_UNDERSTANDING_API_KEY")
    access_token = None
    
    if not api_key:
        scope = "https://cognitiveservices.azure.com/.default"
        try:
            access_token = _get_access_token(scope)
        except ClientAuthenticationError as e:
            return func.HttpResponse(json.dumps({"error": f"Authentication failed: {e}", "correlationId": correlation_id}), status_code=500, mimetype="application/json")
    
    # Build headers based on authentication method
    headers_base = {
        "Content-Type": "application/json",
        "x-correlation-id": correlation_id
    }
    
    if api_key:
        headers_base["Ocp-Apim-Subscription-Key"] = api_key
        logging.info(f"[{correlation_id}] Using API key authentication")
    elif access_token:
        headers_base["Authorization"] = f"Bearer {access_token}"
        logging.info(f"[{correlation_id}] Using Azure AD token authentication")
    else:
        return func.HttpResponse(json.dumps({"error": "No authentication method available. Set CONTENT_UNDERSTANDING_API_KEY or configure managed identity.", "correlationId": correlation_id}), status_code=500, mimetype="application/json")

    # Helper to parse integer parameters with defaults
    def _get_int_param(name: str, default: int) -> int:
        raw = req.params.get(name) or body_all.get(name)
        if raw is None:
            return default
        try:
            return int(raw)
        except ValueError:
            return default

    max_wait_seconds = _get_int_param("maxWaitSeconds", 600)
    max_retries = _get_int_param("maxRetries", 10)
    retry_after_seconds = _get_int_param("retryAfterSeconds", 30)

    # Helper to parse boolean parameters
    def _get_bool_param(name: str, default: bool) -> bool:
        raw = req.params.get(name) or body_all.get(name)
        if raw is None:
            return default
        return str(raw).lower() == "true"

    # Helper to safely parse JSON responses
    def _safe_json(response: requests.Response) -> dict:
        try:
            return response.json()
        except ValueError:
            return {"raw": response.text}

    # Handle GET status check: expects resultId OR operationLocation
    if req.method == "GET":
        result_id = req.params.get("resultId") or body_all.get("resultId")
        operation_location = req.params.get("operationLocation") or body_all.get("operationLocation")
        if not operation_location and result_id:
            operation_location = f"{base_url}/analyzerResults/{result_id}?api-version={api_version}"
        if not operation_location:
            return func.HttpResponse(json.dumps({"error": "Must supply resultId or operationLocation for GET status check.", "correlationId": correlation_id}), status_code=400, mimetype="application/json")

        poll = _get_bool_param("poll", True)  # Default to polling for GET as well

        status_code, result_body = _exponential_backoff_poll(operation_location, headers_base, max_wait_seconds=max_wait_seconds, max_retries=max_retries, correlation_id=correlation_id)
        return func.HttpResponse(json.dumps({
            "correlationId": correlation_id,
            "operationLocation": operation_location,
            "finalStatusCode": status_code,
            "result": result_body
        }), status_code=200, mimetype="application/json")

    # POST submit and optional poll workflow
    url = req.params.get("url") or body_all.get("url")
    data = body_all.get("data") if url is None else None
    if not url and not data:
        missing_payload = {
            "error": "Must provide 'url' or 'data'.",
            "correlationId": correlation_id,
            "received": {
                "query": {k: req.params.get(k) for k in req.params.keys()},
                "bodyKeys": list(body_all.keys()) if isinstance(body_all, dict) else None,
                "bodySample": body_all if isinstance(body_all, dict) else None
            }
        }
        return func.HttpResponse(json.dumps(missing_payload), status_code=400, mimetype="application/json")
    
    payload = {"url": url} if url else {"data": data}
    analyze_endpoint = f"{base_url}/analyzers/{analyzer_id}:analyze?api-version={api_version}"
    poll = _get_bool_param("poll", True)  # Default to polling

    try:
        submit_resp = requests.post(analyze_endpoint, headers=headers_base, json=payload, timeout=60)
    except requests.RequestException as e:
        logging.error(f"[{correlation_id}] Error submitting analyze request: {e}")
        return func.HttpResponse(json.dumps({"error": f"Network error submitting request: {e}", "correlationId": correlation_id}), status_code=502, mimetype="application/json")

    if submit_resp.status_code not in (202, 200):
        failure_body = _safe_json(submit_resp)
        enhanced = {
            "error": "Analyze request failed",
            "statusCode": submit_resp.status_code,
            "upstreamEndpoint": analyze_endpoint,
            "requestPayloadKeys": list(payload.keys()),
            "upstreamResponse": failure_body,
            "correlationId": correlation_id
        }
        return func.HttpResponse(json.dumps(enhanced), status_code=submit_resp.status_code, mimetype="application/json")

    # Extract operation location for polling
    operation_location = submit_resp.headers.get("Operation-Location")
    if not operation_location:
        submit_body = _safe_json(submit_resp)
        operation_id = submit_body.get("operationId")
        if operation_id:
            operation_location = f"{base_url}/analyzerResults/{operation_id}?api-version={api_version}"
        else:
            return func.HttpResponse(json.dumps({"error": "Missing Operation-Location header and operationId in body.", "correlationId": correlation_id}), status_code=502, mimetype="application/json")

    # Poll or return submission acknowledgment
    if poll:
        status_code, result_body = _exponential_backoff_poll(operation_location, headers_base, max_wait_seconds=max_wait_seconds, max_retries=max_retries, correlation_id=correlation_id)
    else:
        status_code, result_body = (202, {"status": "Submitted", "operationLocation": operation_location})

    response_payload = {
        "correlationId": correlation_id,
        "analyzerId": analyzer_id,
        "submissionStatusCode": submit_resp.status_code,
        "operationLocation": operation_location,
        "finalStatusCode": status_code,
        "result": result_body
    }
    
    http_status = 200 if status_code == 200 else status_code
    resp_obj = func.HttpResponse(json.dumps(response_payload), status_code=http_status, mimetype="application/json")
    
    # Add Retry-After header if still processing
    if isinstance(result_body, dict) and result_body.get("status") in {"Running", "NotStarted", "Submitted"}:
        resp_obj.headers["Retry-After"] = str(retry_after_seconds)
    
    return resp_obj
