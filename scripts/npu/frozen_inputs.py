"""Compile immutable run-local inputs and reject source/snapshot changes."""
import hashlib
from pathlib import Path


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class FrozenInputs:
    def __init__(self, root, directory, names):
        self.root, self.directory = Path(root), Path(directory)
        self.inputs, self.external_inputs, self.tracked = {}, {}, {}
        self.copies = []
        for name in names:
            self.inputs[name] = self.copy(self.root / name, self.directory / name)

    def copy(self, original, frozen):
        data = original.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        frozen.parent.mkdir(parents=True, exist_ok=True)
        frozen.write_bytes(data)
        self.copies.append((original, frozen, digest))
        self.verify()
        return digest

    def external(self, original, frozen):
        self.external_inputs[str(original)] = self.copy(original, frozen)

    def track(self, path):
        self.tracked[str(path)] = sha256(path)

    def verify(self):
        for original, frozen, digest in self.copies:
            for path in (original, frozen):
                if sha256(path) != digest:
                    raise RuntimeError('simulation input changed: ' + str(path))
        for path, digest in self.tracked.items():
            if sha256(path) != digest:
                raise RuntimeError('tracked simulation input changed: ' + path)
