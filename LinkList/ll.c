
#include <stdlib.h>

struct ll_node {
	void *data;
	struct ll_node *next;
	struct ll_node *prev;
};


struct ll {
	struct ll_node *head;
	struct ll_node *tail;

	size_t len;
};


struct ll* new_ll() {
	return calloc(1, sizeof(struct ll));
}

void __ll_insertAfter(struct ll_node *newNode, struct ll_node *node) {
	if (newNode == NULL || node == NULL) return;
	struct ll_node *currentNext = node->next;
	node->next = newNode;
	newNode->next = currentNext;
	if (currentNext != NULL) currentNext->prev = newNode;
	newNode->prev = node;
}

struct ll_node* __ll_new_node(size_t blockSize) {
	struct ll_node *node = calloc(1, sizeof(struct ll_node));
	node->data = malloc(blockSize);
	return node;
}

void __ll_free_node(struct ll_node *node) {
	free(node->data);
	free(node);
}

void* ll_push_tail(struct ll* list, size_t blockSize) {
	struct ll_node *newNode = __ll_new_node(blockSize);

	if (list->tail == NULL) {
		list->head = newNode;
	} else {
		list->tail->next = newNode;
		newNode->prev = list->tail;
	}
	list->tail = newNode;
	list->len ++;
	return newNode->data;
}

void* ll_push_head(struct ll* list, size_t blockSize) {
	struct ll_node *newNode = __ll_new_node(blockSize);

	if (list->head == NULL) {
		list->head = newNode;
		list->tail = newNode;
	} else {
		newNode->next = list->head;
		list->head->prev = newNode;
		list->head = newNode;
	}
	list->len ++;
	return newNode->data;
}

size_t ll_size(struct ll *list) {
	return list->len;
}

/**
 * Remove an element from the head of the list.
 *
 * Client is responsible for freeing the returned pointer.
 */
void* ll_pop_head(struct ll *list) {
	if (list->head == NULL)
		return NULL;
	struct ll_node *node = list->head;
	void *ret = node->data;
	list->head = node->next;
	// Case: list length 1
	if (list->head == NULL)
		list->tail = NULL;
	free(node);
	list->len--;
	return ret;
}

void* ll_pop_tail(struct ll *list) {
	if (list->tail == NULL)
		return NULL;
	struct ll_node *node = list->tail;
	void *ret = node->data;
	list->tail = node->prev;
	if (list->tail == NULL)
		list->head = NULL;
	free(node);
	list->len--;
	return ret;
}

void ll_free(struct ll *list) {
	struct ll_node *node = list->head;
	struct ll_node *tmp;
	while (node != NULL) {
		tmp = node->next;
		__ll_free_node(node);
		node = tmp;
	}
	free(list);
}
