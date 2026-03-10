export class Inode {}

export class File extends Inode {
  constructor(data?: Uint8Array | number[]);
  data: Uint8Array;
}

export class OpenFile extends Inode {
  constructor(file: File);
  file: File;
}

export class Directory extends Inode {
  constructor(contents?: Map<string, Inode>);
  contents: Map<string, Inode>;
}

export class PreopenDirectory extends Directory {
  constructor(path: string, contents?: Map<string, Inode>);
  path: string;
}

export class ConsoleStdout extends Inode {
  constructor(write: (text: string) => void);
  write: (text: string) => void;
  static lineBuffered(write: (text: string) => void): ConsoleStdout;
}

export class WASI {
  constructor(
    args?: string[],
    env?: [string, string][],
    fds?: unknown[],
    options?: Record<string, unknown>
  );
  inst: WebAssembly.Instance | null;
  wasiImport: WebAssembly.Imports;
  initialize(instance: WebAssembly.Instance): void;
  setInstance(instance: WebAssembly.Instance): void;
}
