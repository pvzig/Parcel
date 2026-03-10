const encoder = globalThis.TextEncoder
  ? new globalThis.TextEncoder()
  : {
      encode(text) {
        return Uint8Array.from(Buffer.from(text, "utf8"));
      },
    };

const decoder = globalThis.TextDecoder
  ? new globalThis.TextDecoder()
  : {
      decode(bytes) {
        return Buffer.from(bytes).toString("utf8");
      },
    };

const enqueueMicrotask = globalThis.queueMicrotask
  ? globalThis.queueMicrotask.bind(globalThis)
  : (job) => Promise.resolve().then(job);

if (globalThis.AbortController == null) {
  class ParcelAbortSignal {
    constructor() {
      this.aborted = false;
      this.listeners = new Set();
    }

    addEventListener(type, listener) {
      if (type === "abort") {
        this.listeners.add(listener);
      }
    }

    removeEventListener(type, listener) {
      if (type === "abort") {
        this.listeners.delete(listener);
      }
    }

    _abort() {
      if (this.aborted) {
        return;
      }

      this.aborted = true;
      for (const listener of Array.from(this.listeners)) {
        listener();
      }
      this.listeners.clear();
    }
  }

  class ParcelAbortController {
    constructor() {
      this.signal = new ParcelAbortSignal();
    }

    abort() {
      this.signal._abort();
    }
  }

  globalThis.AbortController = ParcelAbortController;
}

function defaultBehavior() {
  return {
    fetchDelayMilliseconds: null,
    fetchErrorName: null,
    fetchErrorMessage: null,
    arrayBufferDelayMilliseconds: null,
    arrayBufferErrorName: null,
    arrayBufferErrorMessage: null,
    jsonDelayMilliseconds: null,
    jsonErrorName: null,
    jsonErrorMessage: null,
    textDelayMilliseconds: null,
    textErrorName: null,
    textErrorMessage: null,
  };
}

function defaultResponse() {
  return {
    status: 200,
    headers: {},
    url: null,
    bodyText: null,
    jsonBody: null,
    behavior: defaultBehavior(),
  };
}

const state = {
  requests: [],
  nextResponse: defaultResponse(),
};

function normalizeHeaders(headers) {
  if (headers == null) {
    return {};
  }

  const normalized = {};
  const append = (key, value) => {
    const name = String(key);
    const stringValue = String(value);
    normalized[name] = normalized[name]
      ? `${normalized[name]}, ${stringValue}`
      : stringValue;
  };

  if (Array.isArray(headers)) {
    for (const entry of headers) {
      if (Array.isArray(entry) && entry.length >= 2) {
        append(entry[0], entry[1]);
      }
    }
    return normalized;
  }

  if (typeof headers.forEach === "function") {
    headers.forEach((value, key) => {
      append(key, value);
    });
    return normalized;
  }

  for (const [key, value] of Object.entries(headers)) {
    append(key, value);
  }
  return normalized;
}

function decodeBody(body) {
  if (body == null) {
    return null;
  }

  if (body instanceof Uint8Array) {
    return decoder.decode(body);
  }

  if (body instanceof ArrayBuffer) {
    return decoder.decode(new Uint8Array(body));
  }

  return String(body);
}

function responseBodyText() {
  if (state.nextResponse.jsonBody !== null) {
    return JSON.stringify(state.nextResponse.jsonBody);
  }

  return state.nextResponse.bodyText ?? "";
}

function makeNamedError(name, message) {
  const error = new Error(message ?? `${name}`);
  error.name = name;
  return error;
}

function parseBehavior(behaviorJSON) {
  if (behaviorJSON == null) {
    return defaultBehavior();
  }

  return {
    ...defaultBehavior(),
    ...JSON.parse(String(behaviorJSON)),
  };
}

function setRuntimeScope(scope) {
  globalThis.self = globalThis;

  if (scope === "worker") {
    delete globalThis.window;
    return;
  }

  globalThis.window = globalThis;
}

function runAbortableOperation({ signal, requestRecord, delayMilliseconds = 0, perform }) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let timer = null;
    let abortListener = null;

    const cleanup = () => {
      if (timer !== null) {
        clearTimeout(timer);
        timer = null;
      }

      if (
        signal &&
        abortListener &&
        typeof signal.removeEventListener === "function"
      ) {
        signal.removeEventListener("abort", abortListener);
      }
    };

    const fail = (error) => {
      if (settled) {
        return;
      }

      settled = true;
      cleanup();
      reject(error);
    };

    const finish = () => {
      if (settled) {
        return;
      }

      settled = true;
      cleanup();

      try {
        resolve(perform());
      } catch (error) {
        reject(error);
      }
    };

    if (signal) {
      if (signal.aborted) {
        requestRecord.aborted = true;
        fail(makeNamedError("AbortError", "The operation was aborted."));
        return;
      }

      abortListener = () => {
        requestRecord.aborted = true;
        enqueueMicrotask(() => {
          fail(makeNamedError("AbortError", "The operation was aborted."));
        });
      };

      if (typeof signal.addEventListener === "function") {
        signal.addEventListener("abort", abortListener, { once: true });
      }
    }

    if (delayMilliseconds > 0) {
      timer = setTimeout(finish, delayMilliseconds);
      return;
    }

    enqueueMicrotask(finish);
  });
}

function makeHeaders(headers) {
  const entries = Object.entries(normalizeHeaders(headers));
  const headersObject = {
    entries,
    forEach(callback) {
      if (this !== headersObject) {
        throw makeNamedError("TypeError", "Illegal invocation");
      }

      for (const [key, value] of this.entries) {
        callback(value, key, headersObject);
      }
    },
  };

  return headersObject;
}

function toArrayBuffer(text) {
  const bytes = encoder.encode(text);
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

function makeResponse(url, requestRecord, signal) {
  const bodyText = responseBodyText();
  const behavior = state.nextResponse.behavior;
  const response = {
    status: state.nextResponse.status,
    url: state.nextResponse.url ?? String(url),
    headers: makeHeaders(state.nextResponse.headers),
    arrayBuffer() {
      if (this !== response) {
        throw makeNamedError("TypeError", "Illegal invocation");
      }

      return runAbortableOperation({
        signal,
        requestRecord,
        delayMilliseconds: behavior.arrayBufferDelayMilliseconds ?? 0,
        perform: () => {
          if (behavior.arrayBufferErrorName) {
            throw makeNamedError(
              behavior.arrayBufferErrorName,
              behavior.arrayBufferErrorMessage
            );
          }

          return toArrayBuffer(bodyText);
        },
      });
    },
    json() {
      if (this !== response) {
        throw makeNamedError("TypeError", "Illegal invocation");
      }

      return runAbortableOperation({
        signal,
        requestRecord,
        delayMilliseconds: behavior.jsonDelayMilliseconds ?? 0,
        perform: () => {
          if (behavior.jsonErrorName) {
            throw makeNamedError(behavior.jsonErrorName, behavior.jsonErrorMessage);
          }

          if (state.nextResponse.jsonBody !== null) {
            return state.nextResponse.jsonBody;
          }

          return JSON.parse(bodyText);
        },
      });
    },
    text() {
      if (this !== response) {
        throw makeNamedError("TypeError", "Illegal invocation");
      }

      return runAbortableOperation({
        signal,
        requestRecord,
        delayMilliseconds: behavior.textDelayMilliseconds ?? 0,
        perform: () => {
          if (behavior.textErrorName) {
            throw makeNamedError(behavior.textErrorName, behavior.textErrorMessage);
          }

          return bodyText;
        },
      });
    },
    clone() {
      if (this !== response) {
        throw makeNamedError("TypeError", "Illegal invocation");
      }

      return makeResponse(url, requestRecord, signal);
    },
  };

  return response;
}

setRuntimeScope("window");

globalThis.__parcelTest = {
  reset() {
    state.requests = [];
    state.nextResponse = defaultResponse();
    setRuntimeScope("window");
  },
  configureRuntimeScope(scope) {
    setRuntimeScope(String(scope));
  },
  configureResponse(status, url, headersJSON, bodyText, jsonBodyJSON, behaviorJSON) {
    state.nextResponse = {
      status: Number(status),
      url: url == null ? null : String(url),
      headers: headersJSON ? normalizeHeaders(JSON.parse(String(headersJSON))) : {},
      bodyText: bodyText == null ? null : String(bodyText),
      jsonBody: jsonBodyJSON ? JSON.parse(String(jsonBodyJSON)) : null,
      behavior: parseBehavior(behaviorJSON),
    };
  },
  recordedRequestsJSON() {
    return JSON.stringify(state.requests);
  },
};

globalThis.fetch = async function fetch(url, init = {}) {
  const requestRecord = {
    url: String(url),
    method: String(init.method ?? "GET"),
    headers: normalizeHeaders(init.headers),
    bodyText: decodeBody(init.body),
    mode: init.mode == null ? null : String(init.mode),
    credentials: init.credentials == null ? null : String(init.credentials),
    cache: init.cache == null ? null : String(init.cache),
    aborted: false,
  };

  state.requests.push(requestRecord);

  const signal = init.signal ?? null;
  const behavior = state.nextResponse.behavior;

  return runAbortableOperation({
    signal,
    requestRecord,
    delayMilliseconds: behavior.fetchDelayMilliseconds ?? 0,
    perform: () => {
      if (behavior.fetchErrorName) {
        throw makeNamedError(behavior.fetchErrorName, behavior.fetchErrorMessage);
      }

      return makeResponse(url, requestRecord, signal);
    },
  });
};
