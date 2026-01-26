#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

// A very short-lived native function.
//
// For very short-lived functions, it is fine to call them on the main isolate.
// They will block the Dart execution while running the native function, so
// only do this for native functions which are guaranteed to be short-lived.
FFI_PLUGIN_EXPORT intptr_t sum(intptr_t a, intptr_t b);

// A longer lived native function, which occupies the thread calling it.
//
// Do not call these kind of native functions in the main isolate. They will
// block Dart execution. This will cause dropped frames in Flutter applications.
// Instead, call these native functions on a separate isolate.
FFI_PLUGIN_EXPORT intptr_t sum_long_running(intptr_t a, intptr_t b);

// --- tree-sitter demo --------------------------------------------------------
//
// The returned string is heap-allocated; release it by calling [ts_free].
//
// language:
//   0 = C
//   1 = JavaScript
FFI_PLUGIN_EXPORT char* ts_parse_sexp(const char* utf8_source, int32_t language);

// Returns newline-delimited tokens for [utf8_source]. Each line is:
//   <start_byte>\t<end_byte>\t<named:0|1>\t<node_type>\n
//
// The returned string is heap-allocated; release it by calling [ts_free].
FFI_PLUGIN_EXPORT char* ts_tokens(const char* utf8_source, int32_t language);

// Frees memory returned by this library (e.g. [ts_parse_sexp]).
FFI_PLUGIN_EXPORT void ts_free(void* ptr);
