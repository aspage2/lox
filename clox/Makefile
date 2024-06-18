
CFILES=$(wildcard *.c)
OFILES=$(patsubst %.c,%.o,$(CFILES))

main: $(OFILES)
	gcc $(OFILES) -o main -fsanitize=address

%.o: %.c
	gcc -fsanitize=address -g -c $<

.PHONY: clean
clean:
	rm *.o main
