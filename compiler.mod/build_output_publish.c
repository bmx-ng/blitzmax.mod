/*
 * Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib
 */

#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif
#include "brl.mod/blitz.mod/blitz.h"

static unsigned long bmx_compiler_output_counter;

BBString * bmx_compiler_temporary_output_path(BBString * publishedPath) {
	char * published = (char *)bbStringToUTF8String(publishedPath);
	const char * slash = strrchr(published, '/');
	const char * backslash = strrchr(published, '\\');
	const char * separator = slash;
	if (backslash && (!separator || backslash > separator)) separator = backslash;
	size_t directoryLength = separator ? (size_t)(separator - published + 1) : 0;
	size_t capacity = directoryLength + 80;
	char * temporary = bbMemAlloc(capacity);
#ifdef _WIN32
	unsigned long processId = (unsigned long)GetCurrentProcessId();
#else
	unsigned long processId = (unsigned long)getpid();
#endif
	unsigned long ordinal = ++bmx_compiler_output_counter;
	if (directoryLength) memcpy(temporary, published, directoryLength);
	snprintf(temporary + directoryLength, capacity - directoryLength, ".bcc2-tmp-%lu-%lu", processId, ordinal);
	BBString * result = bbStringFromUTF8String((const unsigned char *)temporary);
	bbMemFree(temporary);
	bbMemFree(published);
	return result;
}

int bmx_compiler_atomic_replace(BBString * temporaryPath, BBString * publishedPath) {
	char * temporary = (char *)bbStringToUTF8String(temporaryPath);
	char * published = (char *)bbStringToUTF8String(publishedPath);
	int result;
#ifdef _WIN32
	result = MoveFileExA(temporary, published,
		MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
	result = rename(temporary, published) == 0;
#endif
	bbMemFree(temporary);
	bbMemFree(published);
	return result;
}
