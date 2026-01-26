#include "flutter_build_hooks_ffi_example.h"

#include <string.h>

#include <tree_sitter/api.h>

extern const TSLanguage *tree_sitter_c(void);
extern const TSLanguage *tree_sitter_javascript(void);
extern const TSLanguage *tree_sitter_dart(void);

// A very short-lived native function.
//
// For very short-lived functions, it is fine to call them on the main isolate.
// They will block the Dart execution while running the native function, so
// only do this for native functions which are guaranteed to be short-lived.
FFI_PLUGIN_EXPORT intptr_t sum(intptr_t a, intptr_t b) {
#ifdef DEBUG
  return a + b + 1000;
#else
  return a + b;
#endif
}

// A longer-lived native function, which occupies the thread calling it.
//
// Do not call these kind of native functions in the main isolate. They will
// block Dart execution. This will cause dropped frames in Flutter applications.
// Instead, call these native functions on a separate isolate.
FFI_PLUGIN_EXPORT intptr_t sum_long_running(intptr_t a, intptr_t b) {
  // Simulate work.
#if _WIN32
  Sleep(5000);
#else
  usleep(5000 * 1000);
#endif
  return a + b;
}

static const TSLanguage *language_from_id(int32_t language_id) {
  switch (language_id) {
    case 0:
      return tree_sitter_c();
    case 1:
      return tree_sitter_javascript();
    case 2:
      return tree_sitter_dart();
    default:
      return NULL;
  }
}

FFI_PLUGIN_EXPORT char* ts_parse_sexp(const char* utf8_source, int32_t language) {
  if (utf8_source == NULL) {
    return NULL;
  }

  const TSLanguage *ts_language = language_from_id(language);
  if (ts_language == NULL) {
    return NULL;
  }

  TSParser *parser = ts_parser_new();
  if (parser == NULL) {
    return NULL;
  }

  if (!ts_parser_set_language(parser, ts_language)) {
    ts_parser_delete(parser);
    return NULL;
  }

  const uint32_t length = (uint32_t)strlen(utf8_source);
  TSTree *tree = ts_parser_parse_string(parser, NULL, utf8_source, length);
  if (tree == NULL) {
    ts_parser_delete(parser);
    return NULL;
  }

  TSNode root = ts_tree_root_node(tree);
  char *result = ts_node_string(root);

  ts_tree_delete(tree);
  ts_parser_delete(parser);

  return result;
}

FFI_PLUGIN_EXPORT void ts_free(void* ptr) {
  free(ptr);
}

static bool buffer_ensure(char **buffer, size_t *capacity, size_t needed) {
  if (needed <= *capacity) {
    return true;
  }
  size_t new_capacity = *capacity == 0 ? 4096 : *capacity;
  while (new_capacity < needed) {
    new_capacity *= 2;
  }
  char *new_buffer = (char *)realloc(*buffer, new_capacity);
  if (new_buffer == NULL) {
    return false;
  }
  *buffer = new_buffer;
  *capacity = new_capacity;
  return true;
}

static bool buffer_append(
  char **buffer,
  size_t *length,
  size_t *capacity,
  const char *data,
  size_t data_length
) {
  const size_t needed = *length + data_length + 1;
  if (!buffer_ensure(buffer, capacity, needed)) {
    return false;
  }
  memcpy(*buffer + *length, data, data_length);
  *length += data_length;
  (*buffer)[*length] = '\0';
  return true;
}

FFI_PLUGIN_EXPORT char* ts_tokens(const char* utf8_source, int32_t language) {
  if (utf8_source == NULL) {
    return NULL;
  }

  const TSLanguage *ts_language = language_from_id(language);
  if (ts_language == NULL) {
    return NULL;
  }

  TSParser *parser = ts_parser_new();
  if (parser == NULL) {
    return NULL;
  }

  if (!ts_parser_set_language(parser, ts_language)) {
    ts_parser_delete(parser);
    return NULL;
  }

  const uint32_t length = (uint32_t)strlen(utf8_source);
  TSTree *tree = ts_parser_parse_string(parser, NULL, utf8_source, length);
  if (tree == NULL) {
    ts_parser_delete(parser);
    return NULL;
  }

  TSNode root = ts_tree_root_node(tree);
  TSTreeCursor cursor = ts_tree_cursor_new(root);

  char *buffer = NULL;
  size_t buffer_length = 0;
  size_t buffer_capacity = 0;

  while (true) {
    TSNode node = ts_tree_cursor_current_node(&cursor);
    const uint32_t child_count = ts_node_child_count(node);

    if (child_count == 0) {
      const uint32_t start = ts_node_start_byte(node);
      const uint32_t end = ts_node_end_byte(node);
      const bool named = ts_node_is_named(node);
      const char *type = ts_node_type(node);

      char line[512];
      const int written = snprintf(
        line,
        sizeof(line),
        "%u\t%u\t%d\t%s\n",
        start,
        end,
        named ? 1 : 0,
        type
      );
      if (written < 0) {
        free(buffer);
        ts_tree_cursor_delete(&cursor);
        ts_tree_delete(tree);
        ts_parser_delete(parser);
        return NULL;
      }
      if ((size_t)written < sizeof(line)) {
        if (!buffer_append(&buffer, &buffer_length, &buffer_capacity, line, (size_t)written)) {
          free(buffer);
          ts_tree_cursor_delete(&cursor);
          ts_tree_delete(tree);
          ts_parser_delete(parser);
          return NULL;
        }
      } else {
        // Fallback for unusually long type names.
        char *dynamic_line = (char *)malloc((size_t)written + 1);
        if (dynamic_line == NULL) {
          free(buffer);
          ts_tree_cursor_delete(&cursor);
          ts_tree_delete(tree);
          ts_parser_delete(parser);
          return NULL;
        }
        snprintf(
          dynamic_line,
          (size_t)written + 1,
          "%u\t%u\t%d\t%s\n",
          start,
          end,
          named ? 1 : 0,
          type
        );
        const bool ok = buffer_append(
          &buffer,
          &buffer_length,
          &buffer_capacity,
          dynamic_line,
          (size_t)written
        );
        free(dynamic_line);
        if (!ok) {
          free(buffer);
          ts_tree_cursor_delete(&cursor);
          ts_tree_delete(tree);
          ts_parser_delete(parser);
          return NULL;
        }
      }
    }

    if (ts_tree_cursor_goto_first_child(&cursor)) {
      continue;
    }
    if (ts_tree_cursor_goto_next_sibling(&cursor)) {
      continue;
    }

    while (true) {
      if (!ts_tree_cursor_goto_parent(&cursor)) {
        ts_tree_cursor_delete(&cursor);
        ts_tree_delete(tree);
        ts_parser_delete(parser);
        return buffer;
      }
      if (ts_tree_cursor_goto_next_sibling(&cursor)) {
        break;
      }
    }
  }
}

FFI_PLUGIN_EXPORT char* ts_query_captures(
  const char* utf8_source,
  int32_t language,
  const char* utf8_query
) {
  if (utf8_source == NULL || utf8_query == NULL) {
    return NULL;
  }

  const TSLanguage *ts_language = language_from_id(language);
  if (ts_language == NULL) {
    return NULL;
  }

  TSParser *parser = ts_parser_new();
  if (parser == NULL) {
    return NULL;
  }

  if (!ts_parser_set_language(parser, ts_language)) {
    ts_parser_delete(parser);
    return NULL;
  }

  const uint32_t source_length = (uint32_t)strlen(utf8_source);
  TSTree *tree = ts_parser_parse_string(parser, NULL, utf8_source, source_length);
  if (tree == NULL) {
    ts_parser_delete(parser);
    return NULL;
  }

  uint32_t error_offset = 0;
  TSQueryError error_type = TSQueryErrorNone;
  const uint32_t query_length = (uint32_t)strlen(utf8_query);
  TSQuery *query = ts_query_new(
    ts_language,
    utf8_query,
    query_length,
    &error_offset,
    &error_type
  );
  if (query == NULL) {
    ts_tree_delete(tree);
    ts_parser_delete(parser);
    return NULL;
  }

  TSQueryCursor *cursor = ts_query_cursor_new();
  if (cursor == NULL) {
    ts_query_delete(query);
    ts_tree_delete(tree);
    ts_parser_delete(parser);
    return NULL;
  }

  TSNode root = ts_tree_root_node(tree);
  ts_query_cursor_exec(cursor, query, root);

  char *buffer = NULL;
  size_t buffer_length = 0;
  size_t buffer_capacity = 0;

  TSQueryMatch match;
  uint32_t capture_index = 0;
  while (ts_query_cursor_next_capture(cursor, &match, &capture_index)) {
    const TSQueryCapture capture = match.captures[capture_index];
    const TSNode node = capture.node;
    const uint32_t start = ts_node_start_byte(node);
    const uint32_t end = ts_node_end_byte(node);

    uint32_t name_length = 0;
    const char *name = ts_query_capture_name_for_id(
      query,
      capture.index,
      &name_length
    );
    if (name == NULL || name_length == 0) {
      continue;
    }

    char prefix[64];
    const int prefix_written = snprintf(
      prefix,
      sizeof(prefix),
      "%u\t%u\t",
      start,
      end
    );
    if (prefix_written <= 0) {
      continue;
    }

    if (!buffer_append(
          &buffer,
          &buffer_length,
          &buffer_capacity,
          prefix,
          (size_t)prefix_written)) {
      free(buffer);
      ts_query_cursor_delete(cursor);
      ts_query_delete(query);
      ts_tree_delete(tree);
      ts_parser_delete(parser);
      return NULL;
    }

    if (!buffer_append(
          &buffer,
          &buffer_length,
          &buffer_capacity,
          name,
          (size_t)name_length)) {
      free(buffer);
      ts_query_cursor_delete(cursor);
      ts_query_delete(query);
      ts_tree_delete(tree);
      ts_parser_delete(parser);
      return NULL;
    }

    if (!buffer_append(&buffer, &buffer_length, &buffer_capacity, "\n", 1)) {
      free(buffer);
      ts_query_cursor_delete(cursor);
      ts_query_delete(query);
      ts_tree_delete(tree);
      ts_parser_delete(parser);
      return NULL;
    }
  }

  ts_query_cursor_delete(cursor);
  ts_query_delete(query);
  ts_tree_delete(tree);
  ts_parser_delete(parser);
  return buffer;
}
