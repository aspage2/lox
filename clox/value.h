
#ifndef clox_value_h
#define clox_value_h

typedef double Value;

typedef struct {
	int capacity;
	int count;
	Value* data;
} ValueArray;

void initValueArray(ValueArray*);
void writeValueArray(ValueArray*, Value);
void freeValueArray(ValueArray*);

void printValue(Value v);

#endif
