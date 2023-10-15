const PREC = {
	unary: 9,
	multiplicative: 8,
	additive: 7,
	comparative: 6,
	equality: 5,
	and: 4,
	or: 3,
}

function commaSep(rule) {
	return seq(rule, repeat(seq(',', rule)))
}

module.exports = grammar({
	name: "lox",
	extras: $ => [
		$.comment,
		/\s+/,
	],
	rules: {
		source_file: $ => repeat($._statement),
		_statement: $ => choice(
			$.var_declaration,
			$.print_statement,
			$.break_statement,
			$.if_statement,
			$.while_statement,
			$.expression_statement,
			$.block_statement,
			$.function_declaration,
			$.return_statement,
		),
		return_statement: $ => seq("return", optional($._expression), ";"),
		print_statement: $ => seq("print", $._expression, ";"),
		var_declaration: $ => seq(
			"var", 
			field("name", $.ident), 
			optional(seq("=", field("initializer", $._expression))), 
			";"
		),
		break_statement: $ => seq("break", ";"),
		expression_statement: $ => seq($._expression, ";"),
		block_statement: $ => seq("{", repeat($._statement), "}"),
		if_statement: $ => seq("if", "(", $._expression, ")", $._statement),
		while_statement: $ => seq("while", "(", $._expression, ")", $._statement),
		function_declaration: $ => seq(
			"fun",
			field("function", $.ident),
			"(",
			field("args", optional(commaSep($.ident))),
			")",
			"{",
			repeat($._statement),
			"}",
		),
		_expression: $ => choice(
			$._primary,
			$.binary_expression,
		),
		_primary: $ => choice(
			"true",
			"false",
			$.nil,
			$.ident,
			$.number,
			$.string,
			$.call,
			$._grouping,
		),
		call: $ => seq(field("function", $.ident), "(", field("args", optional(commaSep($._expression))), ")"),
		binary_expression: $ => choice(
			prec.left(PREC.multiplicative, seq(
				field("left", $._expression),
				field("operator", choice("*", "/")),
				field("right", $._expression),
			)),
			prec.left(PREC.additive, seq(
				field("left", $._expression),
				field("operator", choice("-", "+")),
				field("right", $._expression),
			)),
			prec.left(PREC.comparative, seq(
				field("left", $._expression),
				field("operator", choice("<", "<=", ">", ">=")),
				field("right", $._expression),
			)),
			prec.left(PREC.equality, seq(
				field("left", $._expression),
				field("operator", choice("==", "!=")),
				field("right", $._expression),
			)),
			prec.left(PREC.and, seq(
				field("left", $._expression),
				field("operator", "and"),
				field("right", $._expression),
			)),
			prec.left(PREC.or, seq(
				field("left", $._expression),
				field("operator", "or"),
				field("right", $._expression),
			)),
		),
		comment: $ => seq("//", /.*/),
		_grouping: $ => seq("(", $._expression, ")"),
		ident: $ => /[_a-zA-z][_a-zA-Z0-9]*/,
		number: $ => /\d+(\.\d*)?/,
		string: $ => /".*"/,
		nil: $ => "nil",
	}
});
