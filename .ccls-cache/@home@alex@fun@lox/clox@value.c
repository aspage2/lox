#include <stdio.h>

#include "memory.h"
#include "value.h"

void initValueArray(ValueArray * arr) {
	arr->count = 0;
	arr->capacity = 0;
	arr->data = NULL;
}

void writeValueArray(ValueArray *arr, Value v) {
	if (arr->count >= arr->capacity) {
		int oldCap = arr->capacity;
		arr->capacity = GROW_CAPACITY(oldCap);
		arr->data = GROW_ARRAY(Value, arr->data, oldCap, arr->capacity);
	}

	arr->data[arr->count] = v;
	arr->count += 1;
}

void freeValueArray(ValueArray *arr) {
	FREE_ARRAY(Value, arr->data, arr->capacity);
	initValueArray(arr);
}

void printValue(Value v) {
	printf("%g", v);
}
