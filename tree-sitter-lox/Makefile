
binding.gyp: grammar.js
	npm run generate

.PHONY: parse
parse:
	npm run parse main.lx

.PHONY: clean
clean:
	rm -rf bindings/ 
	rm -rf src/
	rm -f binding.gyp
	rm -f Cargo.toml
