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
const parcelClearTimeout = globalThis.clearTimeout;
const parcelSetTimeout = globalThis.setTimeout;

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
    bodyReadDelayMilliseconds: null,
    bodyReadErrorName: null,
    bodyReadErrorMessage: null,
    cancelErrorName: null,
    cancelErrorMessage: null,
    omitResponseStatus: false,
    invalidBodyChunk: false,
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
  requestStateWaiters: [],
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

function clearRequestStateWaiters() {
  const waiters = state.requestStateWaiters;
  state.requestStateWaiters = [];

  for (const waiter of waiters) {
    parcelClearTimeout(waiter.timer);
    waiter.resolve(false);
  }
}

function markRequestState(requestRecord, property) {
  requestRecord[property] = true;
  const requestIndex = state.requests.indexOf(requestRecord);
  if (requestIndex < 0) {
    return;
  }

  const remainingWaiters = [];
  for (const waiter of state.requestStateWaiters) {
    if (waiter.requestIndex === requestIndex && waiter.property === property) {
      parcelClearTimeout(waiter.timer);
      waiter.resolve(true);
    } else {
      remainingWaiters.push(waiter);
    }
  }
  state.requestStateWaiters = remainingWaiters;
}

function waitForRequestState(requestIndex, property) {
  if (state.requests[requestIndex]?.[property] === true) {
    return Promise.resolve(true);
  }

  return new Promise((resolve, reject) => {
    const waiter = {
      requestIndex,
      property,
      resolve,
      timer: null,
    };
    waiter.timer = parcelSetTimeout(() => {
      state.requestStateWaiters = state.requestStateWaiters.filter(
        (candidate) => candidate !== waiter
      );
      reject(
        makeNamedError(
          "TimeoutError",
          `Timed out waiting for request ${requestIndex} state '${property}'.`
        )
      );
    }, 1000);
    state.requestStateWaiters.push(waiter);
  });
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
  const promise = new Promise((resolve, reject) => {
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

  // Swift observes these rejections through JavaScriptKit, but Node can still
  // report them as unhandled during abort races unless the source promise has
  // its own rejection observer.
  promise.catch(() => {});
  return promise;
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

function makeBodyStream(bodyText, signal, requestRecord, behavior) {
  const streamState = {
    locked: false,
    consumed: false,
  };

  const stream = {
    getReader() {
      if (this !== stream) {
        throw makeNamedError("TypeError", "Illegal invocation");
      }

      if (streamState.locked) {
        throw makeNamedError("TypeError", "ReadableStream is already locked.");
      }

      streamState.locked = true;

      let released = false;
      const reader = {
        read() {
          if (this !== reader) {
            throw makeNamedError("TypeError", "Illegal invocation");
          }

          if (released) {
            return Promise.reject(
              makeNamedError("TypeError", "Reader has been released.")
            );
          }

          markRequestState(requestRecord, "bodyReadStarted");

          return runAbortableOperation({
            signal,
            requestRecord,
            delayMilliseconds: behavior.bodyReadDelayMilliseconds ?? 0,
            perform: () => {
              if (behavior.bodyReadErrorName) {
                throw makeNamedError(
                  behavior.bodyReadErrorName,
                  behavior.bodyReadErrorMessage
                );
              }

              if (streamState.consumed) {
                return { done: true, value: undefined };
              }

              streamState.consumed = true;
              if (behavior.invalidBodyChunk) {
                return { done: false, value: { invalid: true } };
              }
              return { done: false, value: encoder.encode(bodyText) };
            },
          });
        },
        cancel() {
          markRequestState(requestRecord, "bodyCancelled");
          streamState.consumed = true;

          if (behavior.cancelErrorName) {
            return Promise.reject(
              makeNamedError(
                behavior.cancelErrorName,
                behavior.cancelErrorMessage
              )
            );
          }

          return Promise.resolve();
        },
        releaseLock() {
          markRequestState(requestRecord, "readerReleased");
          released = true;
          streamState.locked = false;
        },
      };

      return reader;
    },
  };

  return stream;
}

function makeResponse(url, requestRecord, signal) {
  const bodyText = responseBodyText();
  const behavior = state.nextResponse.behavior;
  const response = {
    status: behavior.omitResponseStatus ? undefined : state.nextResponse.status,
    url: state.nextResponse.url ?? String(url),
    headers: makeHeaders(state.nextResponse.headers),
    body:
      state.nextResponse.bodyText === null && state.nextResponse.jsonBody === null
        ? null
        : makeBodyStream(bodyText, signal, requestRecord, behavior),
  };

  return response;
}

setRuntimeScope("window");

globalThis.__parcelTest = {
  reset() {
    clearRequestStateWaiters();
    state.requests = [];
    state.nextResponse = defaultResponse();
    setRuntimeScope("window");
    globalThis.fetch = parcelFetch;
    globalThis.clearTimeout = parcelClearTimeout;
  },
  removeFetch() {
    delete globalThis.fetch;
  },
  removeClearTimeout() {
    delete globalThis.clearTimeout;
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
  waitForRequestState(requestIndex, property) {
    return waitForRequestState(Number(requestIndex), String(property));
  },
  recordedRequestsJSON() {
    return JSON.stringify(state.requests);
  },
};

async function parcelFetch(url, init = {}) {
  const requestRecord = {
    url: String(url),
    method: String(init.method ?? "GET"),
    headers: normalizeHeaders(init.headers),
    bodyText: decodeBody(init.body),
    mode: init.mode == null ? null : String(init.mode),
    credentials: init.credentials == null ? null : String(init.credentials),
    cache: init.cache == null ? null : String(init.cache),
    redirect: init.redirect == null ? null : String(init.redirect),
    aborted: false,
    bodyReadStarted: false,
    bodyCancelled: false,
    readerReleased: false,
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
}

globalThis.fetch = parcelFetch;
