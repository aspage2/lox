#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ll.h"

int main(int argc, char **argv) {
	struct ll *list = new_ll();

	for (int i = 1; i < argc; i ++) {
		size_t len = strlen(argv[i]);

		char *ptr = (char *)ll_push_head(list, len+1);
		strncpy(ptr, argv[i], len);
		ptr[len] = 0;
	}

	while (ll_size(list) > 0) {
		char *ptr = (char *)ll_pop_head(list);
		printf("Hello, %s\n", ptr);
		free(ptr);
	}
	ll_free(list);
}
