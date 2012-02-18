/* This file is part of KDevelop
 *
 * Copyright (C) 2010  Miquel Sabaté <mikisabate@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */


#ifndef NODE_H_
#define NODE_H_


#ifdef __cplusplus
extern "C" {
#endif

/**
 * This enumeration contains all the available tokens
 * used by this parser. This values are important for the
 * tests, so don't touch it unless you are really aware of
 * its side effects.
 */
enum node_t {
  token_invalid = -1,
  token_whitespace = 0,
  token_comment = 1,
  token_plus,
  token_minus,
  token_mul,
  token_pow,
  token_div,
  token_mod,
  token_bit_and,
  token_bit_or,
  token_bit_xor,        /* 10 */
  token_kw_and,
  token_kw_or,
  token_kw_not,
  token_or,
  token_and,
  token_lshift,
  token_rshift,
  token_neg,
  token_not,
  token_unary_plus,     /* 20 */
  token_unary_minus,
  token_assign,
  token_op_assign,
  token_assoc,
  token_cmp,
  token_eq,
  token_neq,
  token_eqq,
  token_match,
  token_nmatch,         /* 30 */
  token_greater,
  token_geq,
  token_lesser,
  token_leq,
  token_dot2,
  token_dot3,
  token_ternary,
  token_if,
  token_unless,
  token_while,          /* 40 */
  token_until,
  token_case,
  token_when,
  token_up_begin,
  token_up_end,
  token_for,
  token_begin,
  token_rescue_arg,
  token_rescue,
  token_ensure,         /* 50 */
  token_object,
  token_numeric,
  token_symbol,
  token_body,
  token_function,
  token_module,
  token_class,
  token_singleton_class,
  token_superclass,     /* Not used anymore */
  token_string,         /* 60 */
  token_regexp,
  token_key,
  token_array,
  token_hash,
  token_block,
  token_method_call,
  token_heredoc,
  token_break,
  token_redo,
  token_retry,          /* 70 */
  token_next,
  token_return,
  token_yield,
  token_alias,
  token_defined,
  token_undef,
  token_array_value,
  token__end__,         /* 78 */
};


/**
 * This structure stores errors on the parsing.
 */
struct error_t {
  char * msg;
  int line, col;
  unsigned char valid;
};


/**
 * This is the AST generated by the parser. It contains the tree
 * and some stats that make things easier to the program that is
 * using this parser.
 */
typedef struct {
  struct node * tree;
  struct error_t errors[2];
} RAst;


/**
 * This structure defines a node
 * in the abstract syntax tree
 */
struct node {
/* Node info */
  int kind;
  char * name;
  char * comment;

/* Node's position */
  int startLine, endLine;
  int startCol, endCol;

/* Left/Right childs */
  struct node * l;
  struct node * r;

/* Condition expression */
  struct node * cond;

/* Ensure expression (Exception-AST only) */
  struct node * ensure;

/* List of inner statements */
  struct node * next;
  struct node * last;
};

/*
 * Although it's not used internally, maybe this is more comfortable
 * to the "outside" programmer ;)
 */
typedef struct node Node;


/* Interface to the parser */

/**
 * Generate the AST of a given ruby file.
 *
 * @param path the path where the file is located.
 * @param contents the contents of the file to compile. Set to NULL
 *        if you want that the parser retrieves the contents for you.
 * @return an AST that represents the code.
 */
    RAst * rb_compile_file(const char * path, const char * contents);

/**
 * Free a RubyAst.
 *
 * @param ra the RubyAst you want to free.
 */
void rb_free(RAst * ra);

/**
 * Get the name node.
 *
 * @param n The root node.
 */
struct node * rb_name_node(struct node * n);

/*
 * There are three ways to allocate a node. The simplest one is
 * alloc_node. If the node has also a conditional expression, we
 * should use alloc_cond. Moreover, if the node has an ensure statement,
 * we should use alloc_ensure.
 */
struct node * alloc_node(int kind, struct node * l, struct node * r);
struct node * alloc_cond(int kind, struct node * cond, struct node * l,
                         struct node * r);
struct node * alloc_ensure(int kind, struct node * l, struct node * r,
                           struct node * els, struct node * ensure);


/*
 * These functions play with the next and last attributes of a node.
 * They're useful to create or update a list of nodes or to concatenate
 * two different lists,
 */
struct node * create_list(struct node * head, struct node * tail);
struct node * update_list(struct node * head, struct node * tail);
struct node * concat_list(struct node * head, struct node * tail);
#define pop_list(head, tail) \
  (tail->last == NULL) ? update_list(head, tail) : create_list(head, tail)


/*
 * Auxiliar functions
 */

void print_node(struct node * n);
void print_errors(struct error_t * errors);
void free_ast(struct node * n);
void free_errors(struct error_t * errors);


#ifdef __cplusplus
}
#endif


#endif /* NODE_H_ */
