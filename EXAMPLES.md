# AI Content Understanding Function - Request/Response Examples

**OpenAPI tool examples for Azure AI Agents calling Azure AI Content Understanding.**

This document shows how Azure AI Agents (or any HTTP client) can call this wrapper function to analyze documents using Azure AI Content Understanding.

## Table of Contents
1. [POST: Submit for Analysis (Default Polling)](#post-submit-for-analysis-default-polling)
2. [POST: Submit with Base64 Data](#post-submit-with-base64-data)
3. [POST: Custom Configuration](#post-custom-configuration)
4. [GET: Check Status (Snapshot)](#get-check-status-snapshot)
5. [GET: Check Status with Polling](#get-check-status-with-polling)
6. [Error Responses](#error-responses)

---

## POST: Submit for Analysis (Default Polling)

Submit a document URL and wait for results (default behavior).

### Request
```http
POST /api/ai_content_understanding HTTP/1.1
Host: your-function.azurewebsites.net
Content-Type: application/json
x-ms-function-key: <your-function-key>

{
  "baseUrl": "https://your-aicu-instance.cognitiveservices.azure.com",
  "analyzerId": "prebuilt-invoice",
  "url": "https://example.com/sample-invoice.pdf"
}
```

### Successful Response (200 OK)
```json
{
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "analyzerId": "prebuilt-invoice",
  "submissionStatusCode": 202,
  "operationLocation": "https://your-aicu-instance.cognitiveservices.azure.com/analyzerResults/abc123?api-version=2025-05-01-preview",
  "finalStatusCode": 200,
  "result": {
    "status": "Succeeded",
    "createdDateTime": "2025-10-19T10:30:00Z",
    "lastUpdatedDateTime": "2025-10-19T10:30:15Z",
    "analyzeResult": {
      "documents": [
        {
          "documentIndex": 0,
          "fields": {
            "InvoiceId": {
              "type": "string",
              "value": "INV-001",
              "confidence": 0.98
            },
            "InvoiceDate": {
              "type": "date",
              "value": "2025-10-15",
              "confidence": 0.95
            },
            "VendorName": {
              "type": "string",
              "value": "Acme Corp",
              "confidence": 0.99
            },
            "InvoiceTotal": {
              "type": "number",
              "value": 1250.50,
              "confidence": 0.97
            }
          }
        }
      ]
    }
  }
}
```

### Timeout Response (200 OK with Timeout)
```json
{
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "analyzerId": "prebuilt-invoice",
  "submissionStatusCode": 202,
  "operationLocation": "https://your-aicu-instance.cognitiveservices.azure.com/analyzerResults/abc123?api-version=2025-05-01-preview",
  "finalStatusCode": 200,
  "result": {
    "status": "Timeout",
    "message": "Polling timed out before completion."
  }
}
```

---

## POST: Submit with Base64 Data

Submit base64-encoded document content directly instead of URL.

### Request
```http
POST /api/ai_content_understanding HTTP/1.1
Host: your-function.azurewebsites.net
Content-Type: application/json
x-ms-function-key: <your-function-key>

{
  "baseUrl": "https://your-aicu-instance.cognitiveservices.azure.com",
  "analyzerId": "prebuilt-layout",
  "data": "JVBERi0xLjQKJeLjz9MKMyAwIG9iago8PC9Qcm9kdWNlcihBZG9iZSBQREYgQ3JlYXRvcik+PgplbmRvYmoKMSAwIG9iago8PC9QYWdlcyAyIDAgUi9UeXBlL0NhdGFsb2c+PgplbmRvYmoKMiAwIG9iago8PC9Db3VudCAxL0tpZHNbNCAwIFJdL1R5cGUvUGFnZXM+PgplbmRvYmoKNCAwIG9iago8PC9UeXBlL1BhZ2UvUGFyZW50IDIgMCBSL1Jlc291cmNlczw8L1Byb2NTZXRbL1BERl0+Pi9NZWRpYUJveFswIDAgNjEyIDc5Ml0+PgplbmRvYmoKeHJlZgowIDUKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDczIDAwMDAwIG4gCjAwMDAwMDAxMjAgMDAwMDAgbiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMTc3IDAwMDAwIG4gCnRyYWlsZXIKPDwvUm9vdCAxIDAgUi9TaXplIDU+PgpzdGFydHhyZWYKMjgzCiUlRU9G"
}
```

### Response (200 OK)
```json
{
  "correlationId": "d4e5f6a7-b8c9-0123-def0-1234567890ab",
  "analyzerId": "prebuilt-layout",
  "submissionStatusCode": 202,
  "operationLocation": "https://your-aicu-instance.cognitiveservices.azure.com/analyzerResults/jkl012?api-version=2025-05-01-preview",
  "finalStatusCode": 200,
  "result": {
    "status": "Succeeded",
    "createdDateTime": "2025-10-19T10:40:00Z",
    "lastUpdatedDateTime": "2025-10-19T10:40:12Z",
    "analyzeResult": {
      "pages": [
        {
          "pageNumber": 1,
          "width": 612,
          "height": 792,
          "unit": "pixel",
          "lines": []
        }
      ]
    }
  }
}
```

---

## POST: Custom Configuration

Submit with custom polling configuration and retry behavior.

### Request
```http
POST /api/ai_content_understanding HTTP/1.1
Host: your-function.azurewebsites.net
Content-Type: application/json
x-ms-function-key: <your-function-key>

{
  "baseUrl": "https://your-aicu-instance.cognitiveservices.azure.com",
  "analyzerId": "prebuilt-invoice",
  "url": "https://example.com/complex-invoice.pdf",
  "maxWaitSeconds": 120,
  "maxRetries": 15,
  "retryAfterSeconds": 5
}
```

### Response (200 OK)
Configuration is respected during polling. Response structure same as standard POST response.

---

## GET: Check Status (Snapshot)

Check current status without polling.

### Request
```http
GET /api/ai_content_understanding?resultId=abc123&baseUrl=https://your-aicu-instance.cognitiveservices.azure.com HTTP/1.1
Host: your-function.azurewebsites.net
x-ms-function-key: <your-function-key>
```

### Response - Still Running (200 OK)
```json
{
  "correlationId": "e5f6a7b8-c9d0-1234-ef01-234567890abc",
  "operationLocation": "https://your-aicu-instance.cognitiveservices.azure.com/analyzerResults/abc123?api-version=2025-05-01-preview",
  "statusCode": 200,
  "body": {
    "status": "Running",
    "createdDateTime": "2025-10-19T10:45:00Z",
    "lastUpdatedDateTime": "2025-10-19T10:45:05Z"
  }
}
```

**Response Headers:**
```
Retry-After: 2
x-correlation-id: e5f6a7b8-c9d0-1234-ef01-234567890abc
```

### Response - Completed (200 OK)
```json
{
  "correlationId": "f6a7b8c9-d0e1-2345-f012-34567890abcd",
  "operationLocation": "https://your-aicu-instance.cognitiveservices.azure.com/analyzerResults/abc123?api-version=2025-05-01-preview",
  "statusCode": 200,
  "body": {
    "status": "Succeeded",
    "createdDateTime": "2025-10-19T10:45:00Z",
    "lastUpdatedDateTime": "2025-10-19T10:45:18Z",
    "analyzeResult": {
      "documents": [
        {
          "documentIndex": 0,
          "fields": {
            "InvoiceId": {
              "type": "string",
              "value": "INV-002",
              "confidence": 0.96
            }
          }
        }
      ]
    }
  }
}
```

---

## GET: Check Status with Polling

Check status and wait for completion.

### Request
```http
GET /api/ai_content_understanding?operationLocation=https://your-aicu-instance.cognitiveservices.azure.com/analyzerResults/mno345?api-version=2025-05-01-preview HTTP/1.1
Host: your-function.azurewebsites.net
x-ms-function-key: <your-function-key>
```

### Response (200 OK)
```json
{
  "correlationId": "a7b8c9d0-e1f2-3456-0123-4567890abcde",
  "operationLocation": "https://your-aicu-instance.cognitiveservices.azure.com/analyzerResults/mno345?api-version=2025-05-01-preview",
  "finalStatusCode": 200,
  "result": {
    "status": "Succeeded",
    "createdDateTime": "2025-10-19T10:50:00Z",
    "lastUpdatedDateTime": "2025-10-19T10:50:22Z",
    "analyzeResult": {
      "documents": [
        {
          "documentIndex": 0,
          "fields": {}
        }
      ]
    }
  }
}
```

---

## Error Responses

### 400 Bad Request - Missing Parameters

**Request:**
```http
POST /api/ai_content_understanding HTTP/1.1
Host: your-function.azurewebsites.net
Content-Type: application/json
x-ms-function-key: <your-function-key>

{
  "analyzerId": "prebuilt-invoice"
}
```

**Response:**
```json
{
  "error": "Must provide 'url' or 'data'.",
  "correlationId": "c9d0e1f2-a3b4-5678-2345-67890abcdef0"
}
```

### 400 Bad Request - Missing Base URL

**Request:**
```http
POST /api/ai_content_understanding HTTP/1.1
Host: your-function.azurewebsites.net
Content-Type: application/json
x-ms-function-key: <your-function-key>

{
  "url": "https://example.com/invoice.pdf"
}
```

**Response:**
```json
{
  "error": "Missing baseUrl (query/body) and CONTENT_UNDERSTANDING_BASE_URL not set.",
  "correlationId": "d0e1f2a3-b4c5-6789-3456-7890abcdef01"
}
```

### 400 Bad Request - Missing Result Identifier (GET)

**Request:**
```http
GET /api/ai_content_understanding?baseUrl=https://your-aicu-instance.cognitiveservices.azure.com HTTP/1.1
Host: your-function.azurewebsites.net
x-ms-function-key: <your-function-key>
```

**Response:**
```json
{
  "error": "Must supply resultId or operationLocation for GET status check.",
  "correlationId": "e1f2a3b4-c5d6-7890-4567-890abcdef012"
}
```

### 500 Internal Server Error - Authentication Failed

**Response:**
```json
{
  "error": "Authentication failed: [authentication error details]",
  "correlationId": "f2a3b4c5-d6e7-8901-5678-90abcdef0123"
}
```

### 502 Bad Gateway - Network Error

**Response:**
```json
{
  "error": "Network error submitting request: [network error details]",
  "correlationId": "a3b4c5d6-e7f8-9012-6789-0abcdef01234"
}
```

### 502 Bad Gateway - Upstream Service Error

**Response:**
```json
{
  "error": "Analyze request failed",
  "statusCode": 500,
  "body": {
    "error": {
      "code": "InternalServerError",
      "message": "An internal error occurred."
    }
  },
  "correlationId": "b4c5d6e7-f8a9-0123-7890-abcdef012345"
}
```

---

## Query Parameter Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `baseUrl` | string | env var | Upstream Content Understanding base URL |
| `analyzerId` | string | env var | Analyzer identifier (falls back to DEFAULT_ANALYZER_ID) |
| `api-version` | string | `2025-05-01-preview` | Upstream API version |
| `url` | string | - | Document URL (mutually exclusive with `data`) |
| `data` | string | - | Base64-encoded document (mutually exclusive with `url`) |
| `maxWaitSeconds` | integer | `600` | Maximum cumulative polling wait time |
| `maxRetries` | integer | `10` | Maximum polling attempts |
| `retryAfterSeconds` | integer | `30` | Retry-After header value when still running |

---

## Common Usage Patterns

### Pattern 1: Submit and Wait (Default)
```bash
curl -X POST "https://your-function.azurewebsites.net/api/ai_content_understanding?code=<function-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "baseUrl": "https://your-aicu-instance.cognitiveservices.azure.com",
    "url": "https://example.com/document.pdf"
  }'
```

### Pattern 2: Manual Polling with GET
```bash
# Step 1: Get the operationLocation from a previous submission
OPERATION_LOCATION="https://your-aicu-instance.cognitiveservices.azure.com/analyzerResults/abc123?api-version=2025-05-01-preview"

# Step 2: Poll for results
curl -X GET "https://your-function.azurewebsites.net/api/ai_content_understanding?operationLocation=$OPERATION_LOCATION&code=<function-key>"
```

### Pattern 3: Custom Polling Configuration
```bash
curl -X POST "https://your-function.azurewebsites.net/api/ai_content_understanding?code=<function-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "baseUrl": "https://your-aicu-instance.cognitiveservices.azure.com",
    "url": "https://example.com/large-document.pdf",
    "maxWaitSeconds": 900,
    "maxRetries": 20,
    "retryAfterSeconds": 45
  }'
```

---

## Response Headers

All responses include:
- `Content-Type: application/json`
- `x-correlation-id: <correlation-id>` (for tracing)

Non-terminal responses may include:
- `Retry-After: <seconds>` (when status is Running or NotStarted)

---

## Notes

1. **Correlation IDs**: Automatically generated or reused from `x-correlation-id` request header for distributed tracing.
2. **Authentication**: Supports dual authentication - Managed Identity (DefaultAzureCredential) OR API key (CONTENT_UNDERSTANDING_API_KEY environment variable).
3. **Timeouts**: Network requests timeout after 30s (GET) or 60s (POST). Polling respects `maxWaitSeconds`.
4. **Exponential Backoff**: Polling uses exponential backoff with jitter (10s base, 30s cap, 10-30s jitter).
5. **Environment Variables**: CONTENT_UNDERSTANDING_BASE_URL, CONTENT_UNDERSTANDING_API_KEY, DEFAULT_ANALYZER_ID, APPLICATIONINSIGHTS_CONNECTION_STRING are optional configuration via environment.
6. **Polling Behavior**: GET always polls by default. POST always polls (removed poll parameter).
