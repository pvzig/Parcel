const encoder = new TextEncoder();
const decoder = new TextDecoder();

function defaultResponse() {
  return {
    status: 200,
    headers: {},
    bodyText: "",
  };
}

const state = {
  requests: [],
  nextResponse: defaultResponse(),
};

function normalizeHeaders(headers) {
  const normalized = {};
  if (headers == null) {
    return normalized;
  }

  headers.forEach((value, key) => {
    normalized[String(key)] = String(value);
  });
  return normalized;
}

function decodeBody(body) {
  return body == null ? null : decoder.decode(body);
}

function makeBody(bodyText) {
  return new ReadableStream({
    start(controller) {
      if (bodyText.length > 0) {
        controller.enqueue(encoder.encode(bodyText));
      }
      controller.close();
    },
  });
}

async function parcelFetch(url, init = {}) {
  state.requests.push({
    url: String(url),
    method: String(init.method ?? "GET"),
    headers: normalizeHeaders(init.headers),
    bodyText: decodeBody(init.body),
  });

  return {
    status: state.nextResponse.status,
    statusText: "",
    headers: new Headers(state.nextResponse.headers),
    body: makeBody(state.nextResponse.bodyText),
  };
}

globalThis.__parcelTest = {
  reset() {
    state.requests = [];
    state.nextResponse = defaultResponse();
    globalThis.fetch = parcelFetch;
  },
  configureResponse(status, headersJSON, bodyText) {
    state.nextResponse = {
      status: Number(status),
      headers: JSON.parse(String(headersJSON)),
      bodyText: String(bodyText),
    };
  },
  recordedRequestsJSON() {
    return JSON.stringify(state.requests);
  },
};

globalThis.fetch = parcelFetch;
