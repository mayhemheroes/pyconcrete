/*
 * mayhem/fuzz_decrypt_buffer.c — in-process libFuzzer harness over pyconcrete's
 * native decryption path (_pyconcrete.decrypt_buffer -> fnDecryptBuffer).
 *
 * This is the SAME code the archived file-input CLI target exercised: the pyconcrete
 * executable reads a `.pye` file and hands its bytes to the C function
 * `_pyconcrete.decrypt_buffer(data)` (src/pyconcrete/__init__.py:99), which is
 * `fnDecryptBuffer` in src/pyconcrete_ext/pyconcrete.c. Fuzzing the exe drove a full
 * embedded CPython interpreter per input (≈no native edges, unfuzzable), so we call the
 * decryption C function directly over the attacker-controlled buffer — the real bug
 * surface (AES block/padding handling on a crafted `.pye`).
 */
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stddef.h>
#include <stdint.h>

#include "pyconcrete.h" /* fnDecryptBuffer, g_PyConcreteError */

/* CPython keeps interpreter-lifetime allocations reachable-but-unfreed; those are not
 * defects, so LSan must not flag them. Mayhem's runtime ASAN_OPTIONS does not override a
 * value baked into the binary via this weak hook (the sanctioned mechanism). Real leaks
 * inside the fuzzed decrypt path (PyBytes / OAES ctx) are still balanced by this harness. */
const char *__asan_default_options(void) { return "detect_leaks=0"; }

int LLVMFuzzerInitialize(int *argc, char ***argv) {
  (void)argc;
  (void)argv;
  Py_InitializeEx(0);
  /* fnDecryptBuffer reports errors via g_PyConcreteError (normally set by the module
   * init we don't run here); give it a real exception type so its error paths are valid. */
  if (g_PyConcreteError == NULL) {
    g_PyConcreteError = PyExc_ValueError;
    Py_INCREF(g_PyConcreteError);
  }
  return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  /* An empty buffer is not a meaningful `.pye`; every non-empty input drives the real
   * decrypt path (length gate -> OAES block decrypt -> padding handling). */
  if (size == 0)
    return 0;

  /* Build a bytes object exactly as __init__.py passes the file content. */
  PyObject *args = Py_BuildValue("(y#)", (const char *)data, (Py_ssize_t)size);
  if (args == NULL) {
    PyErr_Clear();
    return 0;
  }

  PyObject *res = fnDecryptBuffer(NULL, args);
  Py_DECREF(args);
  if (res != NULL)
    Py_DECREF(res);
  else
    PyErr_Clear();
  return 0;
}
