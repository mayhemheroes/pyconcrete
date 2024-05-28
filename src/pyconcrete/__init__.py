#!/usr/bin/env python
#
# Copyright 2015 Falldog Hsieh <falldog7@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import imp
import marshal
import struct
import sys
from importlib._bootstrap_external import _get_supported_file_loaders
from importlib.machinery import SOURCE_SUFFIXES, FileFinder, SourceFileLoader

EXT_PYE = '.pye'

__all__ = ["info"]

_pyconcrete_module = None


def import_pyconcrete_pyd():
    """delay import _pyconcrete for testing"""
    global info, _pyconcrete_module
    if _pyconcrete_module:
        return

    from . import _pyconcrete  # noqa: E402

    _pyconcrete_module = _pyconcrete


def decrypt_buffer(data):
    import_pyconcrete_pyd()
    return _pyconcrete_module.decrypt_buffer(data)


def encrypt_file(pyc_filepath, pye_filepath):
    import_pyconcrete_pyd()
    return _pyconcrete_module.encrypt_file(pyc_filepath, pye_filepath)


def info():
    import_pyconcrete_pyd()
    return _pyconcrete_module.info()


# We need to modify SOURCE_SUFFIXES, because it used in importlib.machinery.all_suffixes function which
# called by inspect.getmodulename and we need to be able to detect the module name relative to .pye files
# because .py can be deleted by us
SOURCE_SUFFIXES.append(EXT_PYE)


class PyeLoader(SourceFileLoader):
    @property
    def magic(self):
        if sys.version_info >= (3, 7):
            # reference python source code
            # python/Lib/importlib/_bootstrap_external.py _code_to_timestamp_pyc() & _code_to_hash_pyc()
            # MAGIC + HASH + TIMESTAMP + FILE_SIZE
            magic = 16
        elif sys.version_info >= (3, 3):
            # reference python source code
            # python/Lib/importlib/_bootstrap_external.py _code_to_bytecode()
            # MAGIC + TIMESTAMP + FILE_SIZE
            magic = 12
        else:
            # load pyc from memory
            # reference http://stackoverflow.com/questions/1830727/how-to-load-compiled-python-modules-from-memory
            # MAGIC + TIMESTAMP
            magic = 8
        return magic

    @staticmethod
    def _validate_version(data):
        magic = imp.get_magic()
        ml = len(magic)
        if data[:ml] != magic:
            # convert little-endian byte string to unsigned short
            py_magic = struct.unpack('<H', magic[:2])[0]
            pye_magic = struct.unpack('<H', data[:2])[0]
            raise ValueError("Python version doesn't match with magic: python(%d) != pye(%d)" % (py_magic, pye_magic))

    def get_code(self, fullname):
        if not self.path.endswith(EXT_PYE):
            return super().get_code(fullname)

        path = self.get_filename(fullname)
        data = decrypt_buffer(self.get_data(path))
        self._validate_version(data)
        return marshal.loads(data[self.magic :])

    def get_source(self, fullname):
        if self.path.endswith(EXT_PYE):
            return None
        return super().get_source(fullname)


def install():
    loader_details = [(PyeLoader, SOURCE_SUFFIXES)] + _get_supported_file_loaders()

    sys.path_importer_cache.clear()
    sys.path_hooks.insert(0, FileFinder.path_hook(*loader_details))


install()
