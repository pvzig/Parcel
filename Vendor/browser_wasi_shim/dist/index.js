import { WASI as NodeWASI } from "node:wasi";

export class Inode {}

export class File extends Inode {
  constructor(data = []) {
    super();
    this.data = data instanceof Uint8Array ? data : Uint8Array.from(data);
  }
}

export class OpenFile extends Inode {
  constructor(file) {
    super();
    this.file = file;
  }
}

export class Directory extends Inode {
  constructor(contents = new Map()) {
    super();
    this.contents = contents;
  }
}

export class PreopenDirectory extends Directory {
  constructor(path, contents = new Map()) {
    super(contents);
    this.path = path;
  }
}

export class ConsoleStdout extends Inode {
  constructor(write) {
    super();
    this.write = write;
  }

  static lineBuffered(write) {
    return new ConsoleStdout(write);
  }
}

export class WASI {
  constructor(args = [], env = [], _fds = [], _options = {}) {
    this.inst = null;
    this.nodeWASI = new NodeWASI({
      version: "preview1",
      args,
      env: Object.fromEntries(env),
      preopens: {
        "/": process.cwd(),
      },
      returnOnExit: true,
    });
    this.wasiImport = this.nodeWASI.wasiImport;
  }

  initialize(instance) {
    this.inst = instance;
    return this.nodeWASI.initialize(instance);
  }

  setInstance(instance) {
    this.inst = instance;
  }
}
