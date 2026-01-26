#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include <stdbool.h>

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
//   2 = Dart
FFI_PLUGIN_EXPORT char* ts_parse_sexp(const char* utf8_source, int32_t language);

// Returns newline-delimited tokens for [utf8_source]. Each line is:
//   <start_byte>\t<end_byte>\t<named:0|1>\t<node_type>\n
//
// The returned string is heap-allocated; release it by calling [ts_free].
FFI_PLUGIN_EXPORT char* ts_tokens(const char* utf8_source, int32_t language);

// Runs a tree-sitter query and returns newline-delimited captures.
//
// Each line is:
//   <start_byte>\t<end_byte>\t<capture_name>\n
//
// The returned string is heap-allocated; release it by calling [ts_free].
FFI_PLUGIN_EXPORT char* ts_query_captures(
    const char* utf8_source,
    int32_t language,
    const char* utf8_query);

// Frees memory returned by this library (e.g. [ts_parse_sexp]).
FFI_PLUGIN_EXPORT void ts_free(void* ptr);

// --- tree-sitter incremental document API -----------------------------------
//
// Creates a document (TSParser + last TSTree) for a given language.
// Returns NULL on failure.
FFI_PLUGIN_EXPORT void* ts_doc_new(int32_t language);

// Destroys the document and releases all resources.
FFI_PLUGIN_EXPORT void ts_doc_delete(void* doc);

// Applies an edit to the currently stored tree (ts_tree_edit). Must be called
// before reparsing if you want correct incremental parsing.
FFI_PLUGIN_EXPORT void ts_doc_edit(
    void* doc,
    uint32_t start_byte,
    uint32_t old_end_byte,
    uint32_t new_end_byte,
    uint32_t start_row,
    uint32_t start_col,
    uint32_t old_end_row,
    uint32_t old_end_col,
    uint32_t new_end_row,
    uint32_t new_end_col);

// Re-parses the full source string, reusing the previous tree for incremental
// parsing. Returns true on success.
FFI_PLUGIN_EXPORT bool ts_doc_reparse(void* doc, const char* utf8_source);

// Returns newline-delimited query captures for the currently stored tree.
// Each line is:
//   <start_byte>\t<end_byte>\t<capture_name>\n
//
// Returned string is heap-allocated; free with ts_free.
FFI_PLUGIN_EXPORT char* ts_doc_query_captures(void* doc, const char* utf8_query);
