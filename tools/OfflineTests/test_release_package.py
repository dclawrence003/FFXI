import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
from release_package import verify, rehearse


class PackageChecks(unittest.TestCase):
    def package(self, root, filename, contents=b'original', declared=b'original', name='addons/Example/main.lua'):
        target = root / filename
        manifest = {'format': 'ffxi-addon-source-package-v1', 'source_commit': filename,
                    'files': {name: {'sha256': hashlib.sha256(declared).hexdigest(), 'bytes': len(declared)}}}
        with zipfile.ZipFile(target, 'w') as archive:
            archive.writestr('manifest.json', json.dumps(manifest))
            archive.writestr(name, contents)
        return target

    def test_rejects_tampering_and_traversal(self):
        with tempfile.TemporaryDirectory(prefix='ffxi-package-test-') as tmp:
            root = Path(tmp)
            with self.assertRaises(ValueError):
                verify(self.package(root, 'tampered.zip', b'modified'))
            with self.assertRaises(ValueError):
                verify(self.package(root, 'escape.zip', name='addons/../../escape'))

    def test_restores_previous_package(self):
        with tempfile.TemporaryDirectory(prefix='ffxi-package-test-') as tmp:
            root = Path(tmp)
            old = self.package(root, 'old.zip')
            new = self.package(root, 'new.zip', b'new', b'new', 'addons/Example/new.lua')
            self.assertEqual(rehearse(new, old)['result'], 'PASS')

    def test_unlisted_file_fails(self):
        with tempfile.TemporaryDirectory(prefix='ffxi-package-test-') as tmp:
            archive = self.package(Path(tmp), 'extra.zip')
            with zipfile.ZipFile(archive, 'a') as target:
                target.writestr('addons/Extra/secret.txt', 'unexpected')
            with self.assertRaises(ValueError):
                verify(archive)


if __name__ == '__main__':
    unittest.main()
