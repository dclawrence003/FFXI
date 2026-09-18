"""Execute unittest classes and zero-argument test functions without pytest."""
import importlib.util
from pathlib import Path
import sys
import unittest

suite = unittest.TestSuite()
for index, path in enumerate(sorted(Path(sys.argv[1]).glob('test_*.py'))):
    name = f'offline_case_{index}'
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    suite.addTests(unittest.defaultTestLoader.loadTestsFromModule(module))
    for name, value in vars(module).items():
        if name.startswith('test_') and callable(value) and getattr(value, '__module__', None) == module.__name__:
            suite.addTest(unittest.FunctionTestCase(value))
if suite.countTestCases() == 0:
    raise RuntimeError('No Python cases collected')
result = unittest.TextTestRunner(verbosity=1).run(suite)
sys.exit(0 if result.wasSuccessful() else 1)
