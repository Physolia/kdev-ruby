/* This file is part of KDevelop
 *
 * This file is based on the file parse.y from the MRI, version 1.9.2-p136.
 * So, at this point I must recognize the amazing job ruby developers
 * are doing and specially Yukihiro Matsumoto, the Ruby original author
 * and the one who signed parse.y.
 *
 * Copyright (C) 1993-2007 Yukihiro Matsumoto
 * Copyright (C) 2010 Miquel Sabaté <mikisabate@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.    See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */


%{
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

#include "node.h"


#define YYERROR_VERBOSE 1
#define STACK_SIZE 256
#define BSIZE STACK_SIZE

/* Flags used by the lexer */
/* TODO: in the future they must go as a lex_state thing */
struct flags_t {
    unsigned char eof_reached : 1;
    unsigned char expr_seen : 1;
    unsigned char class_seen : 1;
    unsigned char dot_seen : 1;
    unsigned char last_is_paren : 1;
    unsigned char special_arg : 1;
    unsigned char brace_arg : 1;
    unsigned char def_seen : 1;
    unsigned char in_alias : 1;
    unsigned char symbeg : 1;
    unsigned char mcall : 1;
};

#define eof_reached lexer_flags.eof_reached
#define expr_seen lexer_flags.expr_seen
#define class_seen lexer_flags.class_seen
#define dot_seen lexer_flags.dot_seen
#define last_is_paren lexer_flags.last_is_paren
#define special_arg lexer_flags.special_arg
#define brace_arg lexer_flags.brace_arg
#define def_seen lexer_flags.def_seen
#define in_alias lexer_flags.in_alias
#define symbeg lexer_flags.symbeg
#define mcall lexer_flags.mcall


#define BITSTACK_PUSH(stack, n) ((stack) = ((stack)<<1)|((n)&1))
#define BITSTACK_POP(stack)     ((stack) = (stack) >> 1)
#define BITSTACK_LEXPOP(stack)  ((stack) = ((stack) >> 1) | ((stack) & 1))
#define BITSTACK_SET_P(stack)   ((stack)&1)

#define COND_PUSH(n)    BITSTACK_PUSH(parser->cond_stack, (n))
#define COND_POP()      BITSTACK_POP(parser->cond_stack)
#define COND_LEXPOP()   BITSTACK_LEXPOP(parser->cond_stack)
#define COND_P()        BITSTACK_SET_P(parser->cond_stack)

#define CMDARG_PUSH(n)  BITSTACK_PUSH(parser->cmdarg_stack, (n))
#define CMDARG_POP()    BITSTACK_POP(parser->cmdarg_stack)
#define CMDARG_LEXPOP() BITSTACK_LEXPOP(parser->cmdarg_stack)
#define CMDARG_P()      BITSTACK_SET_P(parser->cmdarg_stack)


/* This structure represents a string/heredoc/regexp term. */
/* TODO: I'm sure it can be simplified */
struct term_t {
    int token;
    char *word; /* TODO: const ? */
    int length;
    unsigned char term;
    unsigned char can_embed : 1;
    unsigned char was_mcall : 1;
};

/* TODO document */
struct comment_t {
    char *comment;
    int line;
};

/*
 * This structure defines the parser. It contains the AST, some
 * flags used for internal reasons and some info about the
 * content to parse.
 */
/* TODO: can be simplified */
struct parser_t {
    /* Abstract Syntax Tree */
    struct node *ast;

    /* Stack of positions */
    struct pos_t *pos_stack;
    struct pos_t auxiliar;
    struct node *last_pos;
    unsigned char call_args : 1;
    int stack_scale;
    int pos_size;
    int name_length;

    /* Flags used by the parser */
    struct flags_t lexer_flags;
    unsigned int cond_stack;
    unsigned int cmdarg_stack;
    int in_def;
    int paren_nest;
    int lpar_beg;
    int expr_mid;
    struct term_t lex_strterm; /* TODO: to the lexer */
    enum ruby_version version;

    /* Errors on the file */
    struct error_t *errors;
    struct error_t *last_error;
    unsigned char warning : 1;
    unsigned char unrecoverable : 1;

    /* Stack of names */
    char *stack[2];
    char *aux;
    int sp;

    /* The last allocated comment + the comment stack    */
    struct comment_t last_comment;
    char *comment_stack[STACK_SIZE];
    int comment_index;

    /* Info about the content to parse */
    /* TODO: optimize all this */
    /* TODO: MRI treats them as const */
    char *lex_p; /* TODO */
    char *lex_prev;
    /* BEGIN: heredoc (can be optimized) */
    char *lex_pend;
    unsigned long line_pend;
    unsigned long column_pend;
    unsigned char here_found : 1;
    /* END: heredoc */
    unsigned long lex_prevc;
    unsigned long cursor;
    unsigned long length;
    unsigned long line;
    unsigned long column;
    unsigned char content_given : 1;
    const char *name;
    char *blob;
};

#include "parser.h"
#define yyparse ruby_yyparse
#define YYLEX_PARAM parser

#define lex_strterm parser->lex_strterm


/* yy's functions */
static int yylex(void *, void *);
static void yyerror(struct parser_t *, const char *);
#define yywarning(msg) { parser->warning = 1; yyerror(parser, (msg)); parser->warning = 0;}

/* The static functions below deal with stacks. */

#define ALLOC_N(kind, l, r) alloc_node(kind, l, r); fix_pos(parser, yyval.n);
#define ALLOC_C(kind, cond, l, r) alloc_cond(kind, cond, l, r); fix_pos(parser, yyval.n);
#define ALLOC_MOD(kind, cond, l, r) ALLOC_C(kind, cond, l, r); copy_range(yyval.n, l, cond);

static void pop_stack(struct parser_t *parser, struct node *n);
#define POP_STACK pop_stack(parser, yyval.n)
static void push_last_comment(struct parser_t *parser);
static void pop_comment(struct parser_t *parser, struct node *n);

static void fix_pos(struct parser_t *parser, struct node *n);
struct node * fix_star(struct parser_t *parser);
static void push_pos(struct parser_t *parser, struct pos_t tokp);
static void pop_pos(struct parser_t *parser, struct node *n);
static void pop_start(struct parser_t *parser, struct node *n);
static void copy_last(struct node *head, struct node *tail);
static void copy_wc_range(struct node *res, struct node *h, struct node *t);
static void copy_wc_range_ext(struct node *res, struct node *h, struct node *t);
#define init_pos_from(n) { n->pos.start_line, n->pos.end_line, n->pos.start_col, n->pos.end_col, 0 }
#define discard_pos() pop_pos(parser, NULL)
#define copy_start(dest, src) ({ dest->pos.start_line = src->pos.start_line; dest->pos.start_col = src->pos.start_col; })
#define copy_end(dest, src) ({ dest->pos.end_line = src->pos.end_line; dest->pos.end_col = src->pos.end_col; })
#define copy_range(dest, src1, src2) ({ copy_start(dest, src1); copy_end(dest, src2); dest->pos.offset = src2->pos.offset; })
#define copy_pos(dest, src) copy_range(dest, src, src);
#define copy_op(op) { parser->aux = strdup(op); parser->name_length = strlen(op);}
#define CONCAT_STRING         parser->auxiliar.end_line = parser->pos_stack[parser->pos_size - 1].end_line; \
                                                    parser->auxiliar.end_col = parser->pos_stack[parser->pos_size - 1].end_col;
%}

%pure_parser
%parse-param { struct parser_t *parser }
%union {
    struct node *n;
    int num;
    struct term_t term;
}

/* Tokens */
%token <n> tCLASS tMODULE tDEF tUNDEF tBEGIN tRESCUE tENSURE tEND tIF tUNLESS
%token <n> tTHEN tELSIF tELSE tCASE tWHEN tWHILE tUNTIL tFOR tBREAK tNEXT tREDO
%token <n> tRETRY tIN tDO tDO_COND tDO_BLOCK tRETURN tYIELD tKWAND tKWOR tKWNOT
%token <n> tALIAS tDEFINED upBEGIN upEND tTRUE tFALSE tNIL tENCODING tDSTAR
%token <n> tFILE tLINE tSELF tSUPER GLOBAL BASE CONST tDO_LAMBDA tCHAR
%token <n> tREGEXP IVAR CVAR NUMERIC FLOAT tNTH_REF tBACKTICK tpEND tSYMBEG
%token <n> tAMPER tAREF tASET tASSOC tCOLON2 tCOLON3 tLAMBDA tLAMBEG tLBRACE
%token <n> tLBRACKET tLPAREN tLPAREN_ARG tSTAR tCOMMENT ARRAY tKEY SYMBOL
%token tSTRING_BEG tSTRING_CONTENT tSTRING_DBEG tSTRING_DEND tSTRING_END tSTRING_DVAR

/* Types */
%type <n> singleton strings string regexp literal numeric cpath rescue_arg
%type <n> top_compstmt top_stmt bodystmt compstmt stmts stmt expr arg primary
%type <n> command command_call method_call if_tail opt_else case_body cases
%type <n> opt_rescue exc_list exc_var opt_ensure args call_args opt_call_args
%type <n> paren_args opt_paren_args super aref_args opt_block_arg block_arg
%type <n> mrhs superclass block_call block_command f_block_optarg f_block_opt
%type <n> const f_arglist f_args f_arg f_arg_item f_optarg f_marg f_marg_list
%type <n> f_margs assoc_list assocs assoc undef_list backref for_var bvar base
%type <n> block_param opt_block_param block_param_def f_opt bv_decls label none
%type <n> lambda f_larglist lambda_body command_args opt_bv_decl lhs do_block
%type <n> mlhs mlhs_head mlhs_basic mlhs_item mlhs_node mlhs_post mlhs_inner
%type <n> fsym variable symbol operation operation2 operation3 other_vars
%type <n> cname fname f_rest_arg f_block_arg opt_f_block_arg f_norm_arg
%type <n> brace_block cmd_brace_block f_bad_arg sym opt_brace_block
%type <n> opt_args_tail args_tail f_kwarg block_args_tail opt_block_args_tail
%type <n> f_kw f_block_kw f_block_kwarg f_kwrest
%type <n> string_contents string_content string_dvar

/* precedence table */
%nonassoc tLOWEST
%nonassoc tLBRACE_ARG

%nonassoc modifier_if modifier_unless modifier_while modifier_until
%left tKWOR tKWAND
%right tKWNOT
%nonassoc tDEFINED
%right '=' tOP_ASGN
%left modifier_rescue
%right '?' ':'
%nonassoc tDOT2 tDOT3
%left tOR
%left tAND
%nonassoc tCMP tEQ tEQQ tNEQ tMATCH tNMATCH
%left '>' tGEQ '<' tLEQ
%left '|' '^'
%left '&'
%left tLSHIFT tRSHIFT
%left '+' '-'
%left '*' '/' '%'
%right tUMINUS_NUM tUMINUS
%right tPOW
%right '!' '~' tUPLUS

%%

top_compstmt: top_stmt  { parser->ast = $1; YYACCEPT; }
    | term              { $$ = 0; YYACCEPT; }
;

top_stmt: none
    | stmt
    | error stmt { $$ = $2; }
;

bodystmt: compstmt opt_rescue opt_else opt_ensure
    {
        $$ = alloc_ensure(token_body, $1, $2, $3, $4);
        copy_wc_range($$, $1, $1);
    }
;

compstmt: stmts opt_terms { $$ = $1; }
;

stmts: none
    | stmt
    | stmts terms stmt  { $$ = ($1 == NULL) ? $3 : update_list($1, $3); }
    | error stmt        { $$ = $2; }
;

stmt: tALIAS fsym fsym
    {
        $$ = ALLOC_N(token_alias, $2, $3); copy_end($$, $3);
    }
    | tALIAS GLOBAL GLOBAL
    {
        /* Ugly as hell, but it works */
        struct node *l = alloc_node(token_object, NULL, NULL);
        l->flags = 3;
        struct node *r = alloc_node(token_object, NULL, NULL);
        r->flags = 3;
        fix_pos(parser, r);
        fix_pos(parser, l);
        pop_stack(parser, l);
        pop_stack(parser, r);
        $$ = ALLOC_N(token_alias, l, r); copy_end($$, r);
    }
    | tALIAS GLOBAL tNTH_REF
    {
        yyerror(parser, "can't make alias for the number variables");
    }
    | tUNDEF undef_list
    {
        $$ = ALLOC_N(token_undef, NULL, $2); copy_last($$, $2);
    }
    | stmt modifier_if expr
    {
        $$ = ALLOC_MOD(token_if, $3, $1, NULL);
    }
    | stmt modifier_unless expr
    {
        $$ = ALLOC_MOD(token_unless, $3, $1, NULL);
    }
    | stmt modifier_while expr
    {
        $$ = ALLOC_MOD(token_while, $3, $1, NULL);
    }
    | stmt modifier_until expr
    {
        $$ = ALLOC_MOD(token_until, $3, $1, NULL);
    }
    | stmt modifier_rescue stmt
    {
        $$ = ALLOC_MOD(token_rescue, $3, $1, NULL);
    }
    | upBEGIN
    {
        if (parser->in_def)
            yyerror(parser, "BEGIN in method");
    }
    '{' compstmt '}'
    {
        $$ = ALLOC_N(token_up_begin, $4, NULL);
        pop_pos(parser, NULL);
        pop_start(parser, $$);
    }
    | upEND '{' compstmt '}'
    {
        $$ = ALLOC_N(token_up_end, $3, NULL);
        pop_pos(parser, NULL);
        pop_start(parser, $$);
    }
    | lhs '=' command_call  { $$ = ALLOC_N(token_assign, $1, $3); }
    | mlhs '=' command_call { $$ = ALLOC_N(token_assign, $1, $3); }
    | variable tOP_ASGN command_call { $$ = ALLOC_N(token_op_assign, $1, $3); }
    | primary '[' opt_call_args rbracket tOP_ASGN command_call
    {
        struct node *aux = alloc_node(token_array_value, $1, $3);
        $$ = alloc_node(token_op_assign, aux, $6);
    }
    | primary '.' base tOP_ASGN command_call
    {
        struct node *aux = alloc_node(token_object, $1, $3);
        $$ = alloc_node(token_op_assign, aux, $5);
    }
    | primary '.' const tOP_ASGN command_call
    {
        struct node *aux = alloc_node(token_object, $1, $3);
        $$ = alloc_node(token_op_assign, aux, $5);
    }
    | primary tCOLON2 const tOP_ASGN command_call
    {
        yyerror(parser, "constant re-assignment");
    }
    | primary tCOLON2 base tOP_ASGN command_call
    {
        struct node *aux = alloc_node(token_object, $1, $3);
        $$ = alloc_node(token_op_assign, aux, $5);
    }
    | backref tOP_ASGN command_call { $$ = ALLOC_N(token_op_assign, $1, $3); }
    | lhs '=' mrhs  { $$ = ALLOC_N(token_assign, $1, $3); }
    | mlhs '=' arg  { $$ = ALLOC_N(token_assign, $1, $3); }
    | mlhs '=' mrhs { $$ = ALLOC_N(token_assign, $1, $3); }
    | expr
    | tpEND { $$ = ALLOC_N(token__end__, NULL, NULL); }
;

expr: command_call
    | expr tKWAND expr      { $$ = ALLOC_N(token_kw_and, $1, $3); discard_pos();    }
    | expr tKWOR expr       { $$ = ALLOC_N(token_kw_or, $1, $3);    discard_pos();  }
    | tKWNOT opt_eol expr   { $$ = ALLOC_N(token_kw_not, $3, NULL); }
    | '!' command_call      { $$ = ALLOC_N(token_not, $2, NULL);    }
    | arg
;

command_call: command | block_command
;

block_command: block_call
    | block_call '.' operation2 command_args
    {
        struct node *aux = update_list($1, $3);
        $$ = alloc_node(token_method_call, aux, $4);
    }
    | block_call tCOLON2 operation2 command_args
    {
        struct node *aux = update_list($1, $3);
        $$ = alloc_node(token_method_call, aux, $4);
    }
;

cmd_brace_block: tLBRACE_ARG opt_block_param compstmt '}'
    {
        discard_pos();
        $$ = ALLOC_N(token_block, $3, $2);
        copy_last($$, $3);
    }
;

command: operation command_args             %prec tLOWEST
    {
        $$ = alloc_node(token_method_call, $1, $2);
        copy_wc_range($$, $1, $2);
    }
    | operation command_args cmd_brace_block
    {
        $$ = alloc_cond(token_method_call, $3, $1, $2);
        copy_wc_range($$, $1, $2);
    }
    | primary '.' operation2 command_args         %prec tLOWEST
    {
        struct node *aux = update_list($1, $3);
        $$ = alloc_node(token_method_call, aux, $4);
        ($4 == NULL) ? copy_wc_range($$, $1, $3) : copy_wc_range($$, $1, $4);
    }
    | primary '.' operation2 command_args cmd_brace_block
    {
        struct node *aux = update_list($1, $3);
        $$ = alloc_cond(token_method_call, $5, aux, $4);
        ($4 == NULL) ? copy_wc_range($$, $1, $3) : copy_wc_range($$, $1, $4);
    }
    | primary tCOLON2 operation2 command_args %prec tLOWEST
    {
        struct node *aux = update_list($1, $3);
        $$ = alloc_node(token_method_call, aux, $4);
        ($4 == NULL) ? copy_wc_range($$, $1, $3) : copy_wc_range($$, $1, $4);
    }
    | primary tCOLON2 operation2 command_args cmd_brace_block
    {
        struct node *aux = update_list($1, $3);
        $$ = alloc_cond(token_method_call, $5, aux, $4);
        ($4 == NULL) ? copy_wc_range($$, $1, $3) : copy_wc_range($$, $1, $4);
    }
    | tSUPER call_args
    {
        $$ = ALLOC_N(token_method_call, $2, NULL);
        copy_last($$, $2);
    }
    | tYIELD call_args
    {
        $$ = ALLOC_N(token_yield, $2, NULL);
        copy_last($$, $2);
    }
    | tRETURN call_args
    {
        $$ = ALLOC_N(token_return, $2, NULL);
        copy_last($$, $2);
    }
    | tBREAK call_args
    {
        $$ = ALLOC_N(token_break, $2, NULL);
        copy_last($$, $2);
    }
    | tNEXT call_args
    {
        $$ = ALLOC_N(token_next, $2, NULL);
        copy_last($$, $2);
    }
;

mlhs: mlhs_basic
    | tLPAREN mlhs_inner rparen { $$ = $2; }
;

mlhs_inner: mlhs_basic
    | tLPAREN mlhs_inner rparen { $$ = $2; }
;

mlhs_basic: mlhs_head
    | mlhs_head mlhs_item { $$ = update_list($1, $2); }
    | mlhs_head tSTAR mlhs_node
    {
        $3->flags = 1;
        $$ = update_list($1, $3);
    }
    | mlhs_head tSTAR mlhs_node ',' mlhs_post
    {
        $3->flags = 1;
        $$ = concat_list($1, update_list($3, $5));
    }
    | mlhs_head tSTAR
    {
        $$ = fix_star(parser);
        $$->flags = 2;
        $$ = update_list($1, $$);
    }
    | mlhs_head tSTAR ',' mlhs_post
    {
        $$ = fix_star(parser);
        $$->flags = 2;
        $$ = update_list($1, $$);
        $$ = concat_list($$, $4);
    }
    | tSTAR mlhs_node               { $$ = $2; $$->flags = 1; }
    | tSTAR mlhs_node ',' mlhs_post { $$ = update_list($2, $4); $2->flags = 1; }
    | tSTAR                         { $$ = fix_star(parser); $$->flags = 2; }
    | tSTAR ',' mlhs_post
    {
        $$ = fix_star(parser);
        $$->flags = 2;
        $$ = update_list($$, $3);
    }
;

mlhs_item: mlhs_node
    | tLPAREN mlhs_inner rparen
    {
        $$ = alloc_node(token_object, $2, NULL);
        copy_wc_range($$, $2, $2);
    }
;

mlhs_head: mlhs_item ','        { $$ = $1; }
    | mlhs_head mlhs_item ','   { $$ = update_list($1, $2); }
;

mlhs_post: mlhs_item            { $$ = $1; }
    | mlhs_post ',' mlhs_item   { $$ = update_list($1, $3); }
;

mlhs_node: variable
    | primary '[' opt_call_args rbracket
    {
        $$ = ALLOC_N(token_array_value, $1, $3);
        copy_wc_range_ext($$, $1, $3);
    }
    | primary '.' base
    {
        $$ = alloc_node(token_method_call, $1, $3);
        copy_wc_range_ext($$, $1, $3);
    }
    | primary tCOLON2 base
    {
        $$ = alloc_node(token_method_call, $1, $3);
        copy_wc_range_ext($$, $1, $3);
    }
    | primary '.' const
    {
        $$ = alloc_node(token_method_call, $1, $3);
        copy_wc_range_ext($$, $1, $3);
    }
    | primary tCOLON2 const
    {
        if (parser->in_def)
            yyerror(parser, "dynamic constant assignment");
        $$ = alloc_node(token_method_call, $1, $3);
        copy_wc_range_ext($$, $1, $3);
    }
    | tCOLON3 const
    {
        if (parser->in_def)
            yyerror(parser, "dynamic constant assignment");
        $$ = $2;
    }
    | backref
;

lhs: variable
    | primary '[' opt_call_args rbracket
    {
        $$ = ALLOC_N(token_array_value, $1, $3);
        copy_wc_range_ext($$, $1, $3);
    }
    | primary '.' base
    {
        $$ = alloc_node(token_method_call, $1, $3);
        copy_range($$, $1, $3);
    }
    | primary tCOLON2 base
    {
        $$ = alloc_node(token_method_call, $1, $3);
        copy_range($$, $1, $3);
    }
    | primary '.' const
    {
        $$ = alloc_node(token_method_call, $1, $3);
        copy_range($$, $1, $3);
    }
    | primary tCOLON2 const
    {
        if (parser->in_def)
            yyerror(parser, "dynamic constant assignment");
        $$ = alloc_node(token_method_call, $1, $3);
        copy_range($$, $1, $3);
    }
    | tCOLON3 const
    {
        if (parser->in_def)
            yyerror(parser, "dynamic constant assignment");
        $$ = $2;
    }
;

cname: BASE
    {
        yyerror(parser, "class/module name must be CONSTANT");
    }
    | const
;

cpath: tCOLON3 cname        { $$ = $2; }
    | cname                 { $$ = $1; }
    | primary tCOLON2 cname { $$ = update_list($1, $3); }
;

/* TODO: reswords, push to the stack ? */
fname: base
    | const
    | op
    {
        $$ = alloc_node(token_object, NULL, NULL);
        $$->name = parser->aux;
        $$->pos.start_line = $$->pos.end_line = parser->line;
        $$->pos.end_col = parser->column;
        $$->pos.start_col = $$->pos.end_col - parser->name_length;
        parser->expr_seen = 1;
        parser->dot_seen = 0;
    }
    | reswords { $$ = ALLOC_N(token_object, NULL, NULL); }
;

fsym: fname | symbol
;

undef_list: fsym
    | undef_list ',' fsym { $$ = update_list($1, $3); }
;

op: '|' { copy_op("|"); } | '^' { copy_op("^"); } | '&' { copy_op("&"); }
    | tCMP { copy_op("<=>"); } | tEQ { copy_op("=="); } | tEQQ { copy_op("===");}
    | tMATCH { copy_op("=~"); } | tNMATCH {copy_op("!~");} | '>' { copy_op(">");}
    | tGEQ { copy_op(">="); } | '<' { copy_op("<"); } | tLEQ { copy_op("<="); }
    | tNEQ {copy_op("!=");} | tLSHIFT {copy_op("<<");} | tRSHIFT {copy_op(">>");}
    | '+' { copy_op("+"); } | '-' { copy_op("-"); } | '*' { copy_op("*"); }
    | tSTAR { copy_op("*"); } | '/' { copy_op("/"); } | '%' { copy_op("%"); }
    | tPOW { copy_op("**"); } | tAREF { copy_op("[]"); } | '`' { copy_op("`");}
    | tUPLUS { copy_op("+"); discard_pos(); } | tASET { copy_op("[]="); }
    | tUMINUS { copy_op("-");discard_pos(); } | tDSTAR { copy_op("**"); }
    | '!' { copy_op("!"); discard_pos(); } | '~' { copy_op("~"); discard_pos(); }
;

reswords: tLINE | tFILE | tENCODING | upBEGIN | upEND | tALIAS | tKWAND
    | tBEGIN | tBREAK | tCASE | tCLASS | tDEF | tDEFINED | tDO | tELSE | tELSIF
    | tEND | tENSURE | tFALSE | tFOR | tIN | tMODULE | tNEXT | tNIL | tKWNOT
    | tKWOR | tREDO | tRESCUE | tRETRY | tRETURN | tSELF | tSUPER | tTHEN | tTRUE
    | tUNDEF | tWHEN | tYIELD | tIF | tUNLESS | tWHILE | tUNTIL
;

arg: lhs '=' arg { $$ = ALLOC_N(token_assign, $1, $3); }
    | lhs '=' arg modifier_rescue arg
    {
        struct node *aux = ALLOC_MOD(token_rescue, $5, $3, NULL);
        $$ = ALLOC_N(token_assign, $1, aux);
    }
    | variable tOP_ASGN arg { $$ = ALLOC_N(token_op_assign, $1, $3); }
    | variable tOP_ASGN arg modifier_rescue arg
    {
        struct node *aux = ALLOC_MOD(token_rescue, $5, $3, NULL);
        $$ = ALLOC_N(token_op_assign, $1, aux);
    }
    | primary '[' opt_call_args rbracket tOP_ASGN arg
    {
        discard_pos();
        struct node *aux = alloc_node(token_array_value, $1, $3);
        copy_wc_range_ext(aux, $1, $3);
        $$ = ALLOC_N(token_op_assign, aux, $6);
    }
    | primary '.' base tOP_ASGN arg
    {
        struct node *aux    = alloc_node(token_object, $1, $3);
        copy_wc_range_ext(aux, $1, $3);
        $$ = ALLOC_N(token_op_assign, aux, $5);
    }
    | primary '.' const tOP_ASGN arg
    {
        struct node *aux    = alloc_node(token_object, $1, $3);
        copy_wc_range_ext(aux, $1, $3);
        $$ = ALLOC_N(token_op_assign, aux, $5);
    }
    | primary tCOLON2 base tOP_ASGN arg
    {
        struct node *aux    = alloc_node(token_object, $1, $3);
        copy_wc_range_ext(aux, $1, $3);
        $$ = ALLOC_N(token_op_assign, aux, $5);
    }
    | primary tCOLON2 const tOP_ASGN arg
    {
        yyerror(parser, "constant re-assignment");
    }
    | tCOLON3 const tOP_ASGN arg
    {
        yyerror(parser, "constant re-assignment");
    }
    | backref tOP_ASGN arg { $$ = ALLOC_N(token_assign, $1, $3); }
    | arg tDOT2 arg { $$ = ALLOC_N(token_dot2, $1, $3); }
    | arg tDOT3 arg { $$ = ALLOC_N(token_dot3, $1, $3);}
    | arg '+' arg { $$ = ALLOC_N(token_plus, $1, $3); }
    | arg '-' arg { $$ = ALLOC_N(token_minus, $1, $3);}
    | arg '*' arg { $$ = ALLOC_N(token_mul, $1, $3);}
    | arg '/' arg { $$ = ALLOC_N(token_div, $1, $3);}
    | arg '%' arg { $$ = ALLOC_N(token_mod, $1, $3);}
    | arg tPOW arg { $$ = ALLOC_N(token_pow, $1, $3);}
    | tUPLUS arg    { $$ = ALLOC_N(token_unary_plus, $2, NULL);    }
    | tUMINUS arg { $$ = ALLOC_N(token_unary_minus, $2, NULL); }
    | arg '|' arg { $$ = ALLOC_N(token_bit_or, $1, $3);    }
    | arg '^' arg { $$ = ALLOC_N(token_bit_xor, $1, $3);    }
    | arg '&' arg { $$ = ALLOC_N(token_bit_and, $1, $3);    }
    | arg tCMP arg    { $$ = ALLOC_N(token_cmp, $1, $3);    }
    | arg '>' arg    { $$ = ALLOC_N(token_greater, $1, $3);    }
    | arg tGEQ arg    { $$ = ALLOC_N(token_geq, $1, $3);    }
    | arg '<' arg    { $$ = ALLOC_N(token_lesser, $1, $3);    }
    | arg tLEQ arg    { $$ = ALLOC_N(token_leq, $1, $3);    }
    | arg tEQ arg    { $$ = ALLOC_N(token_eq, $1, $3);    }
    | arg tEQQ arg    { $$ = ALLOC_N(token_eqq, $1, $3);    }
    | arg tNEQ arg    { $$ = ALLOC_N(token_neq, $1, $3);    }
    | arg tMATCH arg    { $$ = ALLOC_N(token_match, $1, $3); }
    | arg tNMATCH arg    { $$ = ALLOC_N(token_nmatch, $1, $3);    }
    | '!' arg    { $$ = ALLOC_N(token_not, $2, NULL);    }
    | '~' arg { $$ = ALLOC_N(token_neg, $2, NULL);    }
    | arg tLSHIFT arg { $$ = ALLOC_N(token_lshift, $1, $3); }
    | arg tRSHIFT arg { $$ = ALLOC_N(token_rshift, $1, $3); }
    | arg tAND arg { $$ = ALLOC_N(token_and, $1, $3); }
    | arg tOR arg { $$ = ALLOC_N(token_or, $1, $3); }
    | tDEFINED opt_eol arg
    {
        $$ = ALLOC_N(token_defined, $3, NULL);
        copy_end($$, $3);
    }
    | arg '?' arg opt_eol ':' arg
    {
        $$ = alloc_cond(token_ternary, $1, $3, $6);
        copy_range($$, $1, $6);
    }
    | primary
;

aref_args: none
    | args trailer              { $$ = $1; }
    | args ',' assocs trailer   { $$ = update_list($1, $3); }
    | assocs trailer            { $$ = $1; }
;

paren_args: '(' opt_call_args rparen { $$ = $2; }
;

opt_paren_args : none | paren_args
;

opt_call_args: none | call_args
;

call_args: command
    | args opt_block_arg { $$ = update_list($1, $2); }
    | assocs opt_block_arg
    {
        struct node *aux = alloc_node(token_hash, $1, NULL);
        copy_wc_range_ext(aux, $1, $1);
        $$ = update_list(aux, $2);
    }
    | args ',' assocs opt_block_arg
    {
        struct node *aux = alloc_node(token_hash, $3, NULL);
        copy_wc_range_ext(aux, $3, $3);
        struct node *n = update_list(aux, $4);
        $$ = concat_list($1, n);
    }
    | block_arg
;

command_args:
    {
        $<num>$ = parser->cmdarg_stack;
        CMDARG_PUSH(1);
    } call_args
    {
        parser->cmdarg_stack = $<num>$;
        $$ = $2;
    }
;

block_arg: tAMPER arg { $$ = $2; }
;

opt_block_arg: ',' block_arg { $$ = $2; }
    | ',' { $$ = NULL; }
    | none
;

args: arg
    | tSTAR arg             { $$ = $2; }
    | args ',' arg          { $$ = update_list($1, $3); }
    | args ',' tSTAR arg    { $$ = update_list($1, $4); }
;

mrhs: args ',' arg          { $$ = update_list($1, $3); }
    | args ',' tSTAR arg    { $$ = update_list($1, $4); }
    | tSTAR arg             { $$ = $2; }
;

primary: literal
    | strings
    | regexp
    | variable
    | backref
    | tBEGIN bodystmt tEND
    {
        $$ = ALLOC_N(token_begin, $2, NULL);
        pop_start(parser, $$);
    }
    | tLPAREN_ARG expr rparen { $$ = $2; }
    | tLPAREN compstmt ')' { $$ = $2; }
    | primary tCOLON2 const
    {
        struct node *aux = update_list($1, $3);
        $$ = alloc_node(token_method_call, aux, NULL);
        copy_range($$, $1, $3);
    }
    | tCOLON3 const { $$ = $2; }
    | ARRAY { $$ = ALLOC_N(token_array, NULL, NULL); }
    | tLBRACKET aref_args ']'
    {
        $$ = ALLOC_N(token_array, $2, NULL);
        if ($2 != NULL && $2->last != NULL) {
            if ($2->last->pos.end_line >= parser->last_pos->pos.end_line) {
                copy_end($$, $2->last);
            } else {
                copy_end($$, parser->last_pos);
            }
        }
    }
    | tLBRACE assoc_list '}'
    {
        $$ = alloc_node(token_hash, $2, NULL);
        pop_pos(parser, $$);
        pop_start(parser, $$);
    }
    | tRETURN { $$ = ALLOC_N(token_return, NULL, NULL); }
    | tYIELD '(' call_args rparen
    {
        $$ = ALLOC_N(token_yield, $3, NULL);
        copy_last($$, $3);
    }
    | tYIELD '(' rparen { $$ = ALLOC_N(token_yield, NULL, NULL); }
    | tYIELD { $$ = ALLOC_N(token_yield, NULL, NULL); }
    | tDEFINED opt_eol '(' expr rparen
    {
        $$ = ALLOC_N(token_defined, $4, NULL);
        copy_end($$, $4);
    }
    | tKWNOT '(' expr rparen { $$ = ALLOC_N(token_kw_not, $3, NULL);}
    | tKWNOT '(' rparen { $$ = ALLOC_N(token_kw_not, NULL, NULL);}
    | operation brace_block
    {
        $$ = alloc_cond(token_method_call, $2, $1, NULL);
        copy_range($$, $1, $2);
    }
    | method_call opt_brace_block
    {
        $$ = $1;
        $$->cond = $2;
        if ($2)
            copy_end($$, $2);
    }
    | tLAMBDA lambda
    {
        $$ = alloc_cond(token_method_call, $2, NULL, NULL);
        pop_start(parser, $$);
        copy_end($$, $2);
    }
    | tIF expr then compstmt if_tail tEND
    {
        $$ = ALLOC_C(token_if, $2, $4, $5);
        pop_start(parser, $$);
    }
    | tUNLESS expr then compstmt opt_else tEND
    {
        $$ = ALLOC_C(token_unless, $2, $4, $5);
        pop_start(parser, $$);
    }
    | tWHILE { COND_PUSH(1); } expr do { COND_POP(); } compstmt tEND
    {
        $$ = ALLOC_C(token_while, $3, $6, NULL);
        pop_start(parser, $$);
    }
    | tUNTIL { COND_PUSH(1); } expr do { COND_POP(); } compstmt tEND
    {
        $$ = ALLOC_C(token_while, $3, $6, NULL);
        pop_start(parser, $$);
    }
    | tCASE expr opt_terms case_body tEND
    {
        $$ = ALLOC_C(token_case, $2, $4, NULL);
        pop_start(parser, $$);
    }
    | tCASE opt_terms case_body tEND
    {
        $$ = ALLOC_N(token_case, $3, NULL);
        pop_start(parser, $$);
    }
    | tFOR for_var tIN { COND_PUSH(1); } expr do { COND_POP(); } compstmt tEND
    {
        $$ = ALLOC_C(token_for, $5, $8, $2);
        pop_pos(parser, NULL);
        pop_start(parser, $$);
    }
    | tCLASS cpath superclass
    {
        if (parser->in_def)
            yyerror(parser, "class definition in method body");
    }
    bodystmt tEND
    {
        $$ = ALLOC_C(token_class, $3, $5, $2);
        pop_comment(parser, $$);
        pop_start(parser, $$);
    }
    | tCLASS
    {
        parser->class_seen = 1;
    }
    opt_terms tLSHIFT
    {
        parser->class_seen = 0;
    }
    expr term bodystmt tEND
    {
        $$ = ALLOC_N(token_singleton_class, $8, $6);
        pop_comment(parser, $$);
        pop_start(parser, $$);
    }
    | tMODULE cpath
    {
        if (parser->in_def)
            yyerror(parser, "module definition in method body");
    }
    bodystmt tEND
    {
        $$ = ALLOC_N(token_module, $4, $2);
        pop_comment(parser, $$);
        pop_start(parser, $$);
    }
    | tDEF fname
    {
        parser->def_seen = 0;
        parser->in_def++;
    }
    f_arglist bodystmt tEND
    {
        parser->in_def--;
        $$ = ALLOC_C(token_function, $2, $5, $4);
        pop_comment(parser, $$);
        if (parser->pos_size > 0)
            pop_start(parser, $$);
    }
    | tDEF singleton dot_or_colon fname
    {
        parser->def_seen = 0;
        parser->in_def++;
    }
    f_arglist bodystmt tEND
    {
        $$ = alloc_node(token_object, $2, $4);
        copy_range($$, $2, $4);
        $$ = ALLOC_C(token_function, $$, $7, $6);
        $$->flags = 1; /* Class method */
        pop_comment(parser, $$);
        pop_start(parser, $$);
        parser->in_def--;
    }
    | tBREAK    { $$ = ALLOC_N(token_break, NULL, NULL);    }
    | tNEXT     { $$ = ALLOC_N(token_next, NULL, NULL);     }
    | tREDO     { $$ = ALLOC_N(token_redo, NULL, NULL);     }
    | tRETRY    { $$ = ALLOC_N(token_retry, NULL, NULL);    }
;

then: term
    | tTHEN         { discard_pos(); }
    | term tTHEN    { discard_pos(); }
;

do: term
    | tDO_COND      { discard_pos(); }
;

if_tail: opt_else
    | tELSIF expr then compstmt if_tail
    {
        $$ = ALLOC_C(token_if, $2, $4, $5);
        struct pos_t tp = init_pos_from($$);

        pop_pos(parser, $$);
        push_pos(parser, tp);
        if ($4 != NULL)
            copy_end($$, $4);
    }
;

opt_else: none
    | tELSE compstmt
    {
        $$ = ALLOC_N(token_if, $2, NULL);
        struct pos_t tp = init_pos_from($$);

        pop_pos(parser, $$);
        push_pos(parser, tp);
        if ($2 != NULL)
            copy_end($$, $2);
    }
;

for_var: lhs | mlhs
;

f_marg: f_norm_arg              { $$ = $1; }
    | tLPAREN f_margs rparen    { $$ = $2; }
;

f_marg_list: f_marg
    | f_marg_list ',' f_marg { $$ = update_list($1, $3); }
;

f_margs: f_marg_list { $$ = $1; }
    | f_marg_list ',' tSTAR f_norm_arg { $$ = update_list($1, $4); }
    | f_marg_list ',' tSTAR f_norm_arg ',' f_marg_list
    {
        $$ = concat_list($1, update_list($4, $6));
    }
    | f_marg_list ',' tSTAR
    {
        struct node *n = alloc_node(token_object, NULL, NULL);
        $$ = update_list($1, n);
    }
    | f_marg_list ',' tSTAR ',' f_marg_list
    {
        struct node *n = alloc_node(token_object, NULL, NULL);
        $$ = concat_list($1, update_list(n, $5));
    }
    | tSTAR f_norm_arg { $$ = $2; }
    | tSTAR f_norm_arg ',' f_marg_list { $$ = update_list($2, $4); }
    | tSTAR { $$ = alloc_node(token_object, NULL, NULL); }
    | tSTAR ',' f_marg_list
    {
        struct node *n = alloc_node(token_object, NULL, NULL);
        $$ = update_list(n, $3);
    }
;

block_args_tail: f_block_kwarg ',' f_kwrest opt_f_block_arg
    {
        $$ = concat_list($1, update_list($3, $4));
    }
    | f_block_kwarg opt_f_block_arg
    {
        $$ = update_list($1, $2);
    }
    | f_kwrest opt_f_block_arg
    {
        $$ = update_list($1, $2);
    }
    | f_block_arg { $$ = $1; }
;

opt_block_args_tail: ',' block_args_tail { $$ = $2; }
    | /* none */ { $$ = 0; }
;

block_param: f_arg ',' f_block_optarg ',' f_rest_arg opt_block_args_tail
    {
        $$ = concat_list($1, concat_list($3, update_list($5, $6)));
    }
    | f_arg ',' f_block_optarg ',' f_rest_arg ',' f_arg opt_block_args_tail
    {
        $$ = concat_list($1, concat_list($3, create_list($5, update_list($7, $8))));
    }
    | f_arg ',' f_block_optarg opt_block_args_tail
    {
        $$ = concat_list($1, update_list($3, $4));
    }
    | f_arg ',' f_block_optarg ',' f_arg opt_block_args_tail
    {
        $$ = concat_list($1, concat_list($3, update_list($5, $6)));
    }
    | f_arg ',' f_rest_arg opt_block_args_tail
    {
        $$ = update_list($1, update_list($3, $4));
    }
    | f_arg ',' { $$ = $1; }
    | f_arg ',' f_rest_arg ',' f_arg opt_block_args_tail
    {
        $$ = concat_list($1, concat_list($3, update_list($5, $6)));
    }
    | f_arg opt_block_args_tail { $$ = update_list($1, $2); }
    | f_block_optarg ',' f_rest_arg opt_block_args_tail
    {
        $$ = concat_list($1, update_list($3, $4));
    }
    | f_block_optarg ',' f_rest_arg ',' f_arg opt_block_args_tail
    {
        $$ = concat_list($1, create_list($3, update_list($5, $6)));
    }
    | f_block_optarg opt_block_args_tail { $$ = update_list($1, $2); }
    | f_block_optarg ',' f_arg opt_block_args_tail
    {
        $$ = concat_list($1, update_list($3, $4));
    }
    | f_rest_arg opt_block_args_tail { $$ = update_list($1, $2); }
    | f_rest_arg ',' f_arg opt_block_args_tail
    {
        $$ = create_list($1, update_list($3, $4));
    }
    | block_args_tail
;

opt_block_param : none
    | block_param_def
;

block_param_def : '|' opt_bv_decl '|'   { $$ = $2;      }
    | tOR                               { $$ = NULL;    }
    | '|' block_param opt_bv_decl '|'   { $$ = update_list($2, $3); }
;

opt_bv_decl: none
    | ';' bv_decls
    {
        if (parser->version < ruby19) {
            yywarning("Block local variables are only available in Ruby 1.9.x or higher.");
        }
        $$ = $2;
    }
;

bv_decls: bvar
    | bv_decls ',' bvar { $$ = update_list($1, $3); }
;

bvar: base
    | f_bad_arg { $$ = NULL; }
;

lambda:
    {
        $<num>$ = parser->lpar_beg;
        parser->lpar_beg = ++parser->paren_nest;
    }
    f_larglist lambda_body
    {
        parser->lpar_beg = $<num>1;
        discard_pos();
        $$ = ALLOC_N(token_block, $3, $2);
        if ($3 != NULL)
            copy_last($$, $3);
        parser->last_pos = NULL;
    }
;

f_larglist: '(' f_args opt_bv_decl rparen { $$ = update_list($2, $3); }
    | f_args
;

lambda_body: tLAMBEG compstmt '}'   { $$ = $2; }
    | tDO_LAMBDA compstmt tEND      { $$ = $2; }
;

do_block: tDO_BLOCK opt_block_param compstmt tEND
    {
        discard_pos();
        $$ = ALLOC_N(token_block, $3, $2);
        if ($3 != NULL)
            copy_last($$, $3);
        else if ($2 != NULL)
            copy_last($$, $2);
    }
;

block_call: command do_block { $1->cond = $2; $$ = $1; }
    | block_call '.' operation2 opt_paren_args
    {
        struct node *aux = update_list($1, $3);
        $$ = update_list(aux, $4);
    }
    | block_call tCOLON2 operation2 opt_paren_args
    {
        struct node *aux = update_list($1, $3);
        $$ = update_list(aux, $4);
    }
;

method_call: operation paren_args
    {
        $$ = alloc_node(token_method_call, $1, $2);
        copy_wc_range($$, $1, $2);
    }
    | primary '.' operation2 opt_paren_args
    {
        struct node *aux = update_list($1, $3);
        $$ = alloc_node(token_method_call, aux, $4);
        ($4 == NULL) ? copy_wc_range($$, $1, $3) : copy_wc_range($$, $1, $4);
    }
    | primary tCOLON2 operation2 paren_args
    {
        struct node *aux = update_list($1, $3);
        $$ = alloc_node(token_method_call, aux, $4);
        ($4 == NULL) ? copy_range($$, $1, $3) : copy_range($$, $1, $4);
    }
    | primary tCOLON2 operation3
    {
        struct node *aux = update_list($1, $3);
        $$ = alloc_node(token_method_call, aux, NULL);
        copy_range($$, $1, $3);
    }
    | primary '.' paren_args
    {
        $$ = alloc_node(token_method_call, $1, $3);
    }
    | primary tCOLON2 paren_args
    {
        $$ = alloc_node(token_method_call, $1, $3);
    }
    | super paren_args { $$ = $1; $$->r = $2; }
    | super
    | primary '[' opt_call_args rbracket
    {
        $$ = ALLOC_N(token_array_value, $1, $3);
        copy_wc_range_ext($$, $1, $3);
    }
;

opt_brace_block: none
    | brace_block
;

brace_block: '{' opt_block_param compstmt '}'
    {
        discard_pos();
        $$ = ALLOC_N(token_block, $3, $2);
        if ($3 != NULL)
            copy_last($$, $3);
        else if ($2 != NULL)
            copy_last($$, $2);
    }
    | tDO opt_block_param compstmt tEND
    {
        discard_pos();
        $$ = ALLOC_N(token_block, $3, $2);
        if ($3 != NULL)
            copy_last($$, $3);
        else if ($2 != NULL)
            copy_last($$, $2);
    }
;

case_body: tWHEN { parser->expr_seen = 0; } args then compstmt cases
    {
        /* The following statements fixes some issues around positions. */
        $$ = ALLOC_N(token_object, NULL, NULL);
        struct pos_t tp = init_pos_from($$);
        $$ = ALLOC_C(token_when, $3, $5, $6);
        push_pos(parser, tp);
        if ($5 != NULL)
            copy_last($$, $5);
    }
;

cases: opt_else | case_body
;

opt_rescue: tRESCUE rescue_arg then compstmt opt_rescue
    {
         $$ = ALLOC_N(token_rescue, $2, $4);
        struct pos_t tp = init_pos_from($$);

        pop_pos(parser, $$);
        push_pos(parser, tp);
        if ($4 != NULL)
            copy_last($$, $4);
        else if ($2 != NULL)
            copy_end($$, $2);
    }
    | none
;

rescue_arg: exc_list exc_var
    {
        if ($2 != NULL) {
            $$ = alloc_node(token_rescue_arg, $1, $2);
            ($1 != NULL) ? copy_range($$, $1, $2) : copy_range($$, $2, $2);
        } else if ($1 != NULL) {
            $$ = alloc_node(token_rescue_arg, $1, $2);
            copy_range($$, $1, $1);
        } else
            $$ = NULL;
    }
;

exc_list: arg | mrhs | none
;

exc_var: none | tASSOC lhs { $$ = $2; }
;

opt_ensure: none
    | tENSURE compstmt
    {
        $$ = ALLOC_N(token_ensure, $2, NULL);
        struct pos_t tp = init_pos_from($$);

        pop_pos(parser, $$);
        push_pos(parser, tp);
        if ($2 != NULL)
            copy_end($$, $2);
    }
;

literal: numeric | symbol
;

strings: string
    {
        $$ = alloc_node(lex_strterm.token, $1, NULL);
        if (lex_strterm.token == token_heredoc)
            pop_pos(parser, $$);
        else {
            $$->pos.end_line = parser->line;
            $$->pos.end_col = parser->column;
        }
        pop_start(parser, $$);
        $$->pos.offset = parser->cursor;
    }
    | strings string
    {
        if ($1->l != NULL)
            update_list($1->l, $2);
        $1->pos.end_line = parser->line;
        $1->pos.end_col = parser->column;
        $1->pos.offset = parser->cursor;
        $$ = $1;
        pop_pos(parser, NULL); /* Drop the first position of the last string */
    }
;

string: tCHAR
    {
        lex_strterm.token = token_string;
        $$ = 0;
    }
    | tSTRING_BEG string_contents tSTRING_END
    {
        $$ = $2;
    }
;

string_contents: /* none */ { $$ = 0; }
    | string_contents string_content
    {
        if ($1 != NULL)
            $$ = update_list($1, $2);
        else
            $$ = $2;
    }
;

string_content: tSTRING_CONTENT { $$ = 0; }
    | tSTRING_DBEG
    {
        parser->expr_seen = 0;
        $<num>1 = parser->cond_stack;
        $<term>$ = lex_strterm;
        lex_strterm.term = 0;
        lex_strterm.was_mcall = 0;
    }
    compstmt '}'
    {
        parser->expr_seen = 1;
        parser->cond_stack = $<num>1;
        lex_strterm = $<term>2;
        $$ = $3;
        pop_pos(parser, NULL); /* '}' */
    }
    | tSTRING_DVAR
    {
        $<term>$ = lex_strterm;
        lex_strterm.term = 0;
        lex_strterm.was_mcall = 0;
        parser->expr_seen = 0;
    }
    string_dvar
    {
        lex_strterm = $<term>2;
        $$ = $3;
    }
;

string_dvar: backref
    | GLOBAL    { $$ = ALLOC_N(token_object, NULL, NULL); $$->flags = 3; POP_STACK; }
    | IVAR      { $$ = ALLOC_N(token_object, NULL, NULL); $$->flags = 4; POP_STACK; }
    | CVAR      { $$ = ALLOC_N(token_object, NULL, NULL); $$->flags = 5; POP_STACK; }
;

regexp: tREGEXP { $$ = ALLOC_N(token_regexp, NULL, NULL); }
;

symbol: tSYMBEG sym
    {
        $$ = ALLOC_N(token_symbol, NULL, NULL);
        copy_end($$, $2);
        if ($2->name != NULL)
            $$->name = strdup($2->name);
        free_ast($2);
    }
;

sym: fname
    | strings
    | GLOBAL    { $$ = ALLOC_N(token_object, NULL, NULL); $$->flags = 3; POP_STACK; }
    | IVAR      { $$ = ALLOC_N(token_object, NULL, NULL); $$->flags = 4; POP_STACK; }
    | CVAR      { $$ = ALLOC_N(token_object, NULL, NULL); $$->flags = 5; POP_STACK; }
;

numeric: NUMERIC    { $$ = ALLOC_N(token_numeric, NULL, NULL); }
    | FLOAT         { $$ = ALLOC_N(token_numeric, NULL, NULL); $$->flags = 1; }
;

variable: base
    | GLOBAL    { $$ = ALLOC_N(token_object, NULL, NULL); $$->flags = 3; POP_STACK; }
    | IVAR      { $$ = ALLOC_N(token_object, NULL, NULL); $$->flags = 4; POP_STACK; }
    | CVAR      { $$ = ALLOC_N(token_object, NULL, NULL); $$->flags = 5; POP_STACK; }
    | const
    | other_vars
;

other_vars: tNIL    { $$ = ALLOC_N(token_nil, NULL, NULL);      }
    | tSELF         { $$ = ALLOC_N(token_self, NULL, NULL);     }
    | tTRUE         { $$ = ALLOC_N(token_true, NULL, NULL);     }
    | tFALSE        { $$ = ALLOC_N(token_false, NULL, NULL);    }
    | tFILE         { $$ = ALLOC_N(token_file, NULL, NULL);     }
    | tLINE         { $$ = ALLOC_N(token_line, NULL, NULL);     }
    | tENCODING     { $$ = ALLOC_N(token_encoding, NULL, NULL); }
;

backref: tNTH_REF   { $$ = ALLOC_N(token_object, NULL, NULL); POP_STACK; }
;

superclass: term { $$ = NULL; }
    | '<' { parser->expr_seen = 0; } expr term { $$ = $3; }
    | error term { yyerrok; $$ = NULL; }
;

f_arglist: '(' f_args rparen
    {
        $$ = $2;
        parser->expr_seen = 0;
    }
    | f_args term
    {
        $$ = $1;
        parser->expr_seen = 0;
    }
;

args_tail: f_kwarg ',' f_kwrest opt_f_block_arg
    {
        if (parser->version < ruby20) {
            yywarning("Keyword arguments are only available in Ruby 2.0.x or higher.");
        }
        $$ = concat_list($1, update_list($3, $4));
    }
    | f_kwarg opt_f_block_arg
    {
        if (parser->version < ruby20) {
            yywarning("Keyword arguments are only available in Ruby 2.0.x or higher.");
        }
        $$ = update_list($1, $2);
    }
    | f_kwrest opt_f_block_arg
    {
        if (parser->version < ruby20) {
            yywarning("Keyword arguments are only available in Ruby 2.0.x or higher.");
        }
        $$ = update_list($1, $2);
    }
    | f_block_arg
    {
        $$ = $1;
    }
;

opt_args_tail: ',' args_tail    { $$ = $2; }
    | /* none */                { $$ = 0;  }
;

f_args: f_arg ',' f_optarg ',' f_rest_arg opt_args_tail
    {
        $$ = concat_list($1, concat_list($3, concat_list($5, $6)));
    }
    | f_arg ',' f_optarg ',' f_rest_arg ',' f_arg opt_args_tail
    {
        $$ = concat_list($1, concat_list($3, create_list($5, concat_list($7, $8))));
    }
    | f_arg ',' f_optarg opt_args_tail
    {
        $$ = concat_list($1, concat_list($3, $4));
    }
    | f_arg ',' f_optarg ',' f_arg opt_args_tail
    {
        $$ = concat_list($1, concat_list($3, concat_list($5, $6)));
    }
    | f_arg ',' f_rest_arg opt_args_tail
    {
        $$ = concat_list($1, concat_list($3, $4));
    }
    | f_arg ',' f_rest_arg ',' f_arg opt_args_tail
    {
        $$ = concat_list($1, concat_list($3, concat_list($5, $6)));
    }
    | f_arg opt_args_tail
    {
        $$ = concat_list($1, $2);
    }
    | f_optarg ',' f_rest_arg opt_args_tail
    {
        $$ = concat_list($1, concat_list($3, $4));
    }
    | f_optarg ',' f_rest_arg ',' f_arg opt_args_tail
    {
        $$ = concat_list($1, create_list($3, concat_list($5, $6)));
    }
    | f_optarg opt_args_tail
    {
        $$ = concat_list($1, $2);
    }
    | f_optarg ',' f_arg opt_args_tail
    {
        $$ = concat_list($1, concat_list($3, $4));
    }
    | f_rest_arg opt_args_tail
    {
        $$ = concat_list($1, $2);
    }
    | f_rest_arg ',' f_arg opt_args_tail
    {
        $$ = create_list($1, concat_list($3, $4));
    }
    | args_tail
    | none
;

f_bad_arg: CONST    { yyerror(parser, "formal argument cannot be a constant");              }
    | IVAR          { yyerror(parser, "formal argument cannot be an instance variable");    }
    | GLOBAL        { yyerror(parser, "formal argument cannot be a global variable");       }
    | CVAR          { yyerror(parser, "formal argument cannot be a class variable");        }
;

f_norm_arg: f_bad_arg | base
;

f_arg_item: f_norm_arg
    | tLPAREN f_margs rparen { $$ = $2; }
;

f_arg: f_arg_item
    | f_arg ',' f_arg_item { $$ = update_list($1, $3); }
;

f_kw: label arg
    {
        $$ = alloc_node(token_object, $1, $2);
        $$->flags = 4;
        copy_range($$, $1, $2);
    }
;

f_block_kw: label primary
    {
        $$ = alloc_node(token_object, $1, $2);
        $$->flags = 4;
        copy_range($$, $1, $2);
    }
;

f_block_kwarg: f_block_kw               { $$ = $1; }
    | f_block_kwarg ',' f_block_kw      { $$ = update_list($1, $3); }
;

f_kwarg: f_kw           { $$ = $1; }
    | f_kwarg ',' f_kw  { $$ = update_list($1, $3); }
;

kwrest_mark: tPOW | tDSTAR
;

f_kwrest: kwrest_mark base
    {
        $$ = $2;
        $$->flags = 5;
    }
;

f_opt: base '=' arg { $$ = ALLOC_N(token_assign, $1, $3); $1->flags = 3; }
;

f_block_opt: base '=' primary { $$ = ALLOC_N(token_assign, $1, $3); }
;

f_block_optarg    : f_block_opt
    | f_block_optarg ',' f_block_opt { $$ = update_list($1, $3); }
;

f_optarg: f_opt
    | f_optarg ',' f_opt { $$ = update_list($1, $3); }
;

restarg_mark: '*' | tSTAR
;

f_rest_arg: restarg_mark base { $$ = $2; $$->flags = 1; }
    | restarg_mark { $$ = alloc_node(token_object, NULL, NULL); $$->flags = 1; }
;

blkarg_mark: '&' | tAMPER
;

f_block_arg: blkarg_mark base { $$ = $2; $$->flags = 2; }
;

opt_f_block_arg : ',' f_block_arg { $$ = $2; }
    | none
;

singleton: variable { $$ = $1; }
    | '(' expr rparen
    {
        if ($2 == 0)
            yyerror(parser, "can't define singleton method for ().");
        else {
            switch ($2->kind) {
                case token_string:
                case token_regexp:
                case token_numeric:
                case token_symbol:
                case token_array:
                    yyerror(parser, "can't define singleton method for literals");
            }
        }
        $$ = $2;
    }
;

const: CONST { $$ = ALLOC_N(token_object, NULL, NULL); $$->flags = 6; POP_STACK; }
;

base: BASE { $$ = ALLOC_N(token_object, NULL, NULL); POP_STACK; }
;

assoc_list: none
    | assocs trailer { $$ = $1; }
;

assocs: assoc
    | assocs ',' assoc { $$ = update_list($1, $3); }
;

assoc: arg tASSOC arg
    {
        $$ = alloc_node(token_object, $1, $3);
        copy_range($$, $1, $3);
    }
    | label arg
    {
        if (parser->version < ruby19) {
            yywarning("This syntax is only available in Ruby 1.9.x or higher.");
        }
        $$ = alloc_node(token_object, $1, $2);
        copy_range($$, $1, $2);
    }
    | tDSTAR arg
    {
        if (parser->version < ruby20) {
            yywarning("tDSTAR token is only available in Ruby 2.0.x or higher.");
        }
        $$ = $2;
    }
;

operation: base
    | const
;

operation2: base
    | const
    | op { $$ = alloc_node(token_object, NULL, NULL); $$->name = parser->aux; }
;

operation3: base
    | op { $$ = alloc_node(token_object, NULL, NULL); $$->name = parser->aux; }
;

label: tKEY
    {
        $$ = ALLOC_N(token_symbol, NULL, NULL);
        POP_STACK;
    }
;

super: tSUPER { $$ = ALLOC_N(token_super, NULL, NULL); }
;

dot_or_colon: '.' | tCOLON2
;

opt_terms: /* none */ | terms
;

opt_eol: /* none */ | '\n'
;

rparen: opt_eol ')'
;

rbracket: opt_eol ']'
;

trailer: opt_eol | ','
;

term: ';' {yyerrok;} | '\n'
;

terms: term | terms ';' {yyerrok;}
;

none : /* none */ { $$ = NULL; }
;

%%
#undef parser
#undef yylex

#include <ctype.h>
#include "hash.c"

/* TODO */
#define nextc() parser_nextc(parser)
#define pushback() parser_pushback(parser)
#define _unused_(c) (void) c;


/* Let's define some useful macros :D */

#define to_upper(a) (a & ~32)
#define is_upper(c) (c >= 'A' && c <= 'Z')
#define multiline_comment(c) (*(c+1) == 'b' && *(c+2) == 'e' && *(c+3) == 'g' \
                                                            && *(c+4) == 'i' && *(c+5) == 'n')
#define multiline_end(c) (*c == '=' && *(c+1) == 'e' && *(c+2) == 'n' \
                                                    && *(c+3) == 'd')
#define is_simple(c) (c == '(' || c == '{' || c == '[' || c == '|' || c == '<' || c == '/' || c == '$')
#define is_shortcut(c) (to_upper(c) == 'W' || c == 'r' || to_upper(c) == 'Q' \
                        || c == 'x' || to_upper(c) == 'I' || is_simple(c))
/* TODO: dollar and at are already checked by is_valid_identifier */
#define not_sep(c) (is_valid_identifier(c) || is_utf8_digit(c) \
                                        || *c == '_' || *c == '$' || *c == '@')
#define is_special_method(buffer) ((strlen(buffer) > 4) && buffer[0] == '_' && \
                                                                buffer[1] == '_' && buffer[strlen(buffer) - 2] == '_' && \
                                                                buffer[strlen(buffer) - 1] == '_')
#define maybe_heredoc (!parser->class_seen && !parser->dot_seen)

/* TODO: clean */
#define SWAP(a, b, aux) { aux = a; a = b; b = aux; }


static void init_parser(struct parser_t * parser)
{
    parser->content_given = 0;
    parser->ast = NULL;
    parser->blob = NULL;
    parser->lex_p = NULL;
    parser->lex_prev = NULL;
    parser->lex_prevc = 0;
    parser->lex_pend = NULL;
    parser->line_pend = 0;
    parser->column_pend = 0;
    parser->here_found = 0;
    parser->cursor = 0;
    parser->eof_reached = 0;
    parser->expr_seen = 0;
    parser->class_seen = 0;
    parser->dot_seen = 0;
    parser->last_is_paren = 0;
    parser->cond_stack = 0;
    parser->cmdarg_stack = 0;
    parser->special_arg = 0;
    parser->brace_arg = 0;
    parser->in_def = 0;
    parser->in_alias = 0;
    parser->symbeg = 0;
    parser->mcall = 0;
    parser->expr_mid = 0;
    parser->lpar_beg = 0;
    parser->paren_nest = 0;
    parser->def_seen = 0;
    parser->sp = 0;
    parser->line = 1;
    parser->column = 0;
    parser->name = NULL;
    parser->pos_stack = (struct pos_t *) malloc(STACK_SIZE * sizeof(struct pos_t));
    parser->stack_scale = 0;
    parser->pos_size = 0;
    parser->last_pos = NULL;
    parser->call_args = 0;
    parser->auxiliar.end_line = -1;
    parser->errors = NULL;
    parser->last_error = NULL;
    parser->warning = 0;
    parser->unrecoverable = 0;
    parser->last_comment.comment = NULL;
    parser->last_comment.line = 0;
    parser->comment_index = 0;
    lex_strterm.term = 0;
    lex_strterm.word = NULL;
    lex_strterm.was_mcall = 0;
    lex_strterm.token = token_invalid;
}

static void free_parser(struct parser_t *parser)
{
    int index;

    for (index = 0; index < parser->sp; index++)
        free(parser->stack[index]);
    if (parser->pos_stack != NULL)
        free(parser->pos_stack);
    if (lex_strterm.word)
        free(lex_strterm.word);
    if (!parser->content_given)
        free(parser->blob);
}

/* Read the file's source code and allocate it for further inspection. */
static int retrieve_source(struct parser_t *p, const char *path)
{
    int length;

    /* Open specified file */
    FILE * fd = fopen(path, "r");
    if (!fd) {
        fprintf(stderr, "Cannot open file: %s\n", path);
        return 0;
    }

    fseek(fd, 0, SEEK_END);
    length = ftell(fd);
    fseek(fd, 0, SEEK_SET);

    if (!length)
        return 0;
    p->blob = (char *) malloc(sizeof(char) * length);

    if (!p->blob) {
        fprintf(stderr, "Cannot store contents\n");
        return 0;
    }
    fread(p->blob, length, 1, fd);
    if (ferror(fd)) {
        fprintf(stderr, "Reading error\n");
        return 0;
    }
    p->length = length;
    p->lex_p = p->blob;
    return 1;
}

/*
 * Some macros to make easier the UTF-8 support
 */
#define is_utf(c) ((c & 0xC0) != 0x80)
#define is_special(c) (utf8_charsize(c) > 1)
#define is_identchar(c) (is_utf8_alnum(c) || *c == '_')

/*
 * This function is really simple. It steps over a char of
 * the string s, that is encoded in UTF-8. The result varies on the
 * number of bytes that encodes a single character following the UTF-8
 * rules. Therefore, this function will return 1 if the character
 * is in plain-ASCII, and greater than 1 otherwise.
 */
static int utf8_charsize(const char *s)
{
    int size = 0;
    int i = 0;

    do {
        i++;
        size++;
    } while (s[i] && !is_utf(s[i]));
    return size;
}

static int is_utf8_alpha(const char *str)
{
    return is_special(str) ? 1 : isalpha(*str);
}

static int is_utf8_alnum(const char *str)
{
    return is_special(str) ? 1 : isalnum(*str);
}

static int is_utf8_graph(const char *str)
{
    return is_special(str) ? 1 : isgraph(*str);
}

static int is_utf8_digit(const char *str)
{
    return is_special(str) ? 0 : isdigit(*str);
}

static int is_valid_identifier(const char *c)
{
    if (is_utf8_alpha(c))
        return 1;
    else if (*c == '$' && is_utf8_graph(c + 1) && !is_utf8_digit(c + 1))
        return 1;
    else if ((*c == '_' || *c == '@') && is_utf8_alpha(c + 1))
        return 1;
    else if (*c == '@' && *(c + 1) == '@' && (is_utf8_alpha(c + 2) || *(c + 2) == '_'))
        return 1;
    return 0;
}

static int parser_nextc(struct parser_t *parser)
{
    int c;

    if (parser->eof_reached)
        return -1;
    if ((unsigned int) (parser->lex_p - parser->blob) >= parser->length)
        return -1;

    parser->lex_prev = parser->lex_p;
    parser->lex_prevc = parser->column;
    c = (unsigned char) *parser->lex_p++;
    if (c == '\n') {
        if (parser->here_found) {
            parser->line = parser->line_pend;
            parser->column = parser->column_pend;
            parser->lex_p = parser->lex_pend + 1;
            parser->here_found = 0;
        }
        parser->line++;
        parser->column = -1;
    }
    parser->column++;
    return c;
}

static void parser_pushback(struct parser_t *parser)
{
    parser->column--;
    parser->lex_p--;
    if (*parser->lex_p == '\n') {
        parser->line--;
        parser->column = parser->lex_prevc;
    }
}

static int parse_heredoc_identifier(struct parser_t *parser)
{
    /* TODO: buffer to some lexer buffer ? */
    char *buffer = (char *) malloc(BSIZE * sizeof(char));
    char *ptr = buffer;
    int count = BSIZE, scale = 0;
    char c = nextc(); /* TODO: ugly */
    unsigned char quote_seen = 0, term = ' ';
    unsigned char dash_seen = 0;

    /* Check for <<- case */
    if (c == '-') {
        dash_seen = 1;
        c = nextc();
    }
    /* And now surrounding quotes */
    if (c == '\'' || c == '"' || c == '`') {
        term = c;
        c = nextc();
        quote_seen = 1;
    }
    if (!quote_seen && !is_identchar(parser->lex_prev)) {
        if (dash_seen)
            pushback();
        return 0;
    }

    for (;;) {
        /* If quote was seen, anything except the term is accepted */
        if (quote_seen) {
            if (c == term || !is_utf8_graph(parser->lex_prev))
                break;
        } else if (!is_identchar(parser->lex_prev))
            break;
        if (!count) {
            scale++;
            buffer = (char *) realloc(buffer, (BSIZE << scale) * sizeof(char));
        }
        *ptr++ = c;
        c = nextc();
        if (c < 0) {
            free(buffer);
            yyerror(parser, "unterminated here document identifier");
            return 0;
        }
    }
    *ptr = '\0';
    pushback();

    lex_strterm.term = 1;
    lex_strterm.can_embed = dash_seen;
    lex_strterm.word = buffer;
    lex_strterm.length = ptr - buffer;
    lex_strterm.was_mcall = parser->mcall;
    lex_strterm.token = token_heredoc;
    parser->lex_pend = parser->lex_p + quote_seen;
    parser->line_pend = parser->line;
    parser->column_pend = parser->column;
    return 1;
}

static int parse_heredoc(struct parser_t *parser)
{
    char aux[lex_strterm.length];
    char c = nextc();
    int i = 0;
    int ax = 0;

    /* Skip until next line */
    while (c != -1 && c != '\n')
        c = nextc();

    do {
        c = nextc();

        /* Ignore initial spaces if dash seen */
        if (i == 0 && lex_strterm.can_embed)
            while (isspace(c) || c == '\n')
                c = nextc();
        if (c == '#' && *(parser->lex_prev - 1) != '\\') {
            c = nextc();
            switch (c) {
                case '$': case '@':
                    parser->column -= ax;
                    pushback();
                    return tSTRING_DVAR;
                case '{':
                    parser->column -= ax;
                    return tSTRING_DBEG;
            }
        }
        aux[i] = c;
        if (c == '\n') {
            if ((lex_strterm.length == i) && !strncmp(lex_strterm.word, aux, i)) {
                pushback();
                free(lex_strterm.word);
                lex_strterm.word = NULL;
                return tSTRING_END;
            }
            i = -1;
        } else
            ax += utf8_charsize(parser->lex_prev) - 1;
        if (i >= lex_strterm.length)
            i = -1;
        i++;
    } while (c != -1);
    return token_invalid;
}

/* Return what's the char that closes c */
static char closing_char(char c)
{
    switch (c) {
        case '[': return ']';
        case '(': return ')';
        case '<': return '>';
        case '{': return '}';
        default: return c;
    }
}

static int guess_kind(struct parser_t *parser, char c)
{
    if (!isalpha(c))
        return token_string;

    switch (c) {
        case 'Q': case 'q': case 'x': return token_string;
        case 'I': case 'i':
            if (parser->version < ruby20) {
                yywarning("This shortcut is only available in Ruby 2.0.x or higher.");
            }
        case 'W': case 'w': return token_array;
        case 's': return token_symbol;
        case 'r': return token_regexp;
        default:
            yyerror(parser, "unknown type of %string");
            return 0;
    }
}

/* Push name to the stack */
static void push_stack(struct parser_t *parser, const char *buf)
{
    parser->stack[parser->sp] = strdup(buf);
    parser->sp++;
}

/* Pop name from the stack. */
static void pop_stack(struct parser_t *parser, struct node *n)
{
    if (n != NULL)
        n->name = parser->stack[0];
    parser->stack[0] = parser->stack[1];
    parser->stack[1] = NULL;
    parser->sp--;
}

/* TODO: lex_pos changes everything */
static void push_pos(struct parser_t *parser, struct pos_t tokp)
{
    int scale = STACK_SIZE * parser->stack_scale;

    parser->pos_size++;
    if (parser->pos_size > STACK_SIZE) {
        parser->pos_size = 1;
        parser->stack_scale++;
        scale += STACK_SIZE;
        parser->pos_stack = (struct pos_t *) realloc(parser->pos_stack, scale * sizeof(struct pos_t));
    }
    tokp.offset = parser->cursor;
    parser->pos_stack[parser->pos_size + scale - 1] = tokp;
}

static void pop_pos(struct parser_t *parser, struct node *n)
{
    int scale = STACK_SIZE * parser->stack_scale;
    int pos = parser->pos_size - 1 + scale;
    struct pos_t tokp = parser->pos_stack[pos];

    if (n != NULL) {
        n->pos.start_line = tokp.start_line;
        n->pos.start_col = tokp.start_col;
        n->pos.end_line = tokp.end_line;
        n->pos.end_col = tokp.end_col;
        n->pos.offset = tokp.offset;
    }
    parser->pos_size--;
    if (parser->pos_size == 0 && parser->stack_scale > 0) {
        parser->stack_scale--;
        parser->pos_size = STACK_SIZE;
        scale -= STACK_SIZE;
        parser->pos_stack = (struct pos_t *) realloc(parser->pos_stack, scale * sizeof(struct pos_t));
    }
}

static void pop_start(struct parser_t *parser, struct node *n)
{
    n->pos.start_line = parser->pos_stack[parser->pos_size - 1].start_line;
    n->pos.start_col = parser->pos_stack[parser->pos_size - 1].start_col;
    pop_pos(parser, NULL);
}

static void copy_wc_range(struct node *res, struct node *h, struct node *t)
{
    if (t != NULL)
        (t->last != NULL) ? copy_range(res, h, t->last) : copy_range(res, h, t);
}

static void copy_wc_range_ext(struct node *res, struct node *h, struct node *t)
{
    if (t != NULL)
        (t->last != NULL) ? copy_range(res, h, t->last) : copy_range(res, h, t);
    else
        copy_range(res, h, h);
}

static void copy_last(struct node *h, struct node *t)
{
    (t->last != NULL) ? copy_end(h, t->last) : copy_end(h, t);
}

static void push_last_comment(struct parser_t *parser)
{
    if ((parser->line - parser->last_comment.line) < 2)
        parser->comment_stack[parser->comment_index] = parser->last_comment.comment;
    else
        parser->comment_stack[parser->comment_index] = NULL;
    parser->comment_index++;
    parser->last_comment.comment = NULL;
}

static void pop_comment(struct parser_t *parser, struct node *n)
{
    if (parser->comment_index > 0) {
        parser->comment_index--;
        n->comment = parser->comment_stack[parser->comment_index];
    }
}

/*
 * The following macros are helpers to the fix_pos function.
 */

#define has_operators(kind) ((kind > 1 && kind < token_neg && kind != token_kw_not) || \
                                                        (kind > token_unary_minus && kind < token_ternary))
#define is_unary(kind) (kind >= token_neg && kind <= token_unary_minus)


static void fix_pos(struct parser_t *parser, struct node *n)
{
    int kind;
    struct node *aux;

    if (!n)
        return;

    kind = n->kind;
    if (has_operators(kind)) {
        copy_start(n, n->l);
        aux = (n->r->last != NULL) ? n->r->last : n->r;
        copy_end(n, aux);
        n->pos.offset = aux->pos.offset;
    } else if (is_unary(kind) || kind == token_kw_not) {
        pop_pos(parser, n);
        n->pos.end_line = n->l->pos.end_line;
        n->pos.end_col = n->l->pos.end_col;
    } else {
        pop_pos(parser, n);
        parser->last_pos = n;
    }
}

struct node * fix_star(struct parser_t *parser)
{
    struct node *res = alloc_node(token_object, NULL, NULL);
    res->pos.start_line = res->pos.end_line = parser->auxiliar.start_line;
    res->pos.start_col = parser->auxiliar.start_col;
    res->pos.end_col = res->pos.start_col + 1;
    parser->auxiliar.end_line = -1;
    return res;
}

/*
 * The following macros and functions make all the magic of fetching comments.
 */

#define __check_buffer_size(N) { \
  if (count > N) { \
    count = 0; \
    scale++; \
    buffer = (char *) realloc(buffer, scale * 1024); \
  } \
}

#define __handle_comment_eol { \
  c++; curs++; \
  i = 0; \
  parser->line++; \
}

static void store_comment(struct parser_t *parser, char *comment)
{
    if (parser->last_comment.comment != NULL)
        free(parser->last_comment.comment);
    parser->last_comment.comment = comment;
    parser->last_comment.line = parser->line;
}

static int is_indented_comment(char *c)
{
    char *original = c;

    for (; *c == ' ' || *c == '\t'; ++c);
    return (*c == '#') ? (c - original) : 0;
}

static void set_comment(struct parser_t *parser)
{
    int c, count = 0, scale = 0;
    char *buffer = (char *) malloc(1024); /* TODO: BSIZE or ? */

    pushback();
    for (;; ++count) {
        c = nextc();
        if (c != '#' && !is_indented_comment(parser->lex_prev))
            break;
        while (c == '#' && c != -1)
            c = nextc();

        if (c != '\n') {
            for (; c != -1; count++) {
                __check_buffer_size(1000);
                buffer[count] = c;
                c = nextc();
                if (c == '\n') {
                    buffer[++count] = c;
                    break;
                }
            }
        } else
            buffer[count] = c;
    }

    if (c != -1)
        pushback();
    buffer[count] = '\0';
    store_comment(parser, buffer);
}

static int parse_string(struct parser_t *parser)
{
    register int c = *parser->lex_p;
    int next = *(parser->lex_p + 1);

    if (c == '\\' && (next == lex_strterm.term || next == '\\')) {
        parser->lex_p += 2;
        parser->column += 2;
        return tSTRING_CONTENT;
    }

    if (c == lex_strterm.term) {
        nextc();
        return tSTRING_END;
    }

    /* TODO */
    /* TODO: maybe the c value can mark more about it ? p.e. -2 means EOF, -1 EOL, ... */
    if ((unsigned int) (parser->lex_p - parser->blob) >= parser->length) {
        parser->eof_reached = 1;
        yyerror(parser, "unterminated string meets end of file");
        return -1;
    }

    if (lex_strterm.can_embed && c == '#') {
        nextc();
        switch (*parser->lex_p) {
            case '$': case '@':
                return tSTRING_DVAR;
            case '{':
                c = nextc();
                return tSTRING_DBEG;
        }
        pushback();
    }

    /* TODO: document why we re-use next and c like a boss. */
    next = utf8_charsize(parser->lex_p);
    c = next - 1;
    while (next-- > 0)
        nextc();
    parser->column -= c;
    return tSTRING_CONTENT;
}

static void parse_re_options(struct parser_t *parser)
{
    char aux[64]; /* TODO: use buffer from lexbuf */
    int c = *parser->lex_p;

    while (isalpha(c)) {
        if (c != 'i' && c != 'm' && c != 'x' && c != 'o' &&
            c != 'u' && c != 'e' && c != 's' && c != 'n') {
            sprintf(aux, "unknown regexp option - %c", c);
            yyerror(parser, aux);
            return;
        }
        c = nextc();
    }
    pushback();
}

#define IS_SPCARG(c) (CMDARG_P() && space_seen && !isspace(c))

/*
 * This is the lexer. It reads the source code (blob) and provides tokens to
 * the parser. It also updates the necessary flags.
 */
static int parser_yylex(struct parser_t *parser)
{
    register int c;
    int bc = 0; /* TODO: register ? */
    char *cp;
    char lexbuf[BSIZE]; /* TODO: to the parser struct ¿? */
    int space_seen = 0; /* TODO: short ? char ? */
    struct pos_t tokp = {-1, -1, -1, -1, 0};

    /*
     * TODO:
     *  - User parser->lex_p instead of bc = nextc() to avoid overhead
     *    in some cases.
     */

    /*
     * TODO
     * Positions:
     *  - Sometimes we don't have to push the position.
     *  - We don't have to set the tokp all the time.
     */

    /* String/Regexp/Heredoc parsing */
    /* TODO */
    if (lex_strterm.term) {
        if (lex_strterm.token == token_heredoc) {
            c = parse_heredoc(parser);
            if (c == tSTRING_END) {
                tokp.end_line = parser->line;
                tokp.end_col = parser->column;
                push_pos(parser, tokp);
                SWAP(parser->line, parser->line_pend, space_seen);
                SWAP(parser->column, parser->column_pend, space_seen);
                SWAP(parser->lex_p, parser->lex_pend, cp);
                lex_strterm.term = 0;
                parser->here_found = 1;
                parser->expr_seen = 1;
                lex_strterm.was_mcall = 0; /* TODO: WTF ?! */
            }
        } else {
            c = parse_string(parser);
            if (c == tSTRING_END) {
                if (lex_strterm.token == token_regexp && isalpha(*parser->lex_p))
                    parse_re_options(parser);
                lex_strterm.term = 0;
                parser->expr_seen = 1;
            }
        }
        return c;
    } else if (lex_strterm.token == token_heredoc && lex_strterm.was_mcall) {
        lex_strterm.was_mcall = 0;
        lex_strterm.token = 0;
        parser->mcall = 0;
        return ')';
    }

retry:
    c = nextc();

    tokp.start_line = parser->line;
    tokp.start_col = parser->column - 1;

    if (isdigit(c)) {
        cp = lexbuf;
        goto tnum;
    }

    /* TODO: store last state ? */
    switch (c) {
        case '\0':      /* NULL */
        case EOF:       /* end of script */
            return 0;

        /* white spaces */
        case ' ': case '\t': case '\f': case '\r':
        case '\13': /* vertical tab */
            space_seen = 1;
            goto retry;
        case '#':
            set_comment(parser);
        eol:
        case '\n':
            if (!parser->expr_seen || parser->dot_seen)
                goto retry;
            parser->dot_seen = 0;
            CMDARG_PUSH(0);
            parser->in_alias = 0;
            parser->expr_seen = 0;
            return '\n';
        case '=':
            bc = nextc();
            parser->expr_seen = 0;
            if (bc == '=') {
                bc = nextc();
                if (bc == '=')
                    return tEQQ;
                pushback();
                return tEQ;
            }
            if (bc == '~')
                return tMATCH;
            if (bc == '>')
                return tASSOC;
            if (multiline_comment(parser->lex_prev - 1)) {
                parser->column += 4;
                parser->lex_p += 4;
                while (!multiline_end(parser->lex_prev))
                    nextc();
                parser->column += 3;
                parser->lex_p += 3;
                parser->expr_seen = 1;
                goto eol;
            }
            break;
        case '[':
            parser->paren_nest++;
            CMDARG_PUSH(0);
            if (parser->dot_seen || parser->def_seen || parser->symbeg || parser->in_alias) {
                parser->expr_seen = 0;
                bc = nextc();
                if (bc == ']') {
                    space_seen = 0;
                    parser->symbeg = 0;
                    bc = nextc();
                    if (bc == '=')
                        return tASET;
                    pushback();
                    return tAREF;
                } else if (!parser->def_seen) {
                    tokp.end_col = parser->column;
                    push_pos(parser, tokp);
                    COND_PUSH(0);
                    return c;
                }
                break;
            }
            tokp.end_col = parser->column;
            push_pos(parser, tokp);
            if (!parser->expr_seen || space_seen) {
                parser->expr_seen = 0;
                return tLBRACKET;
            }
            parser->expr_seen = 0;
            COND_PUSH(0);
            return c;
        case ']':
            parser->paren_nest--;
            parser->expr_seen = 1;
            parser->brace_arg = 1;
            CMDARG_LEXPOP();
            COND_LEXPOP();
            return c;
        case '<':
            parser->expr_seen = 0;
            bc = nextc();
            if (bc == '<') {
                bc = nextc();
                if (bc == '=')
                    return tOP_ASGN;
                pushback();
                if (maybe_heredoc) {
                    if (parse_heredoc_identifier(parser)) {
                        push_pos(parser, tokp);
                        return tSTRING_BEG;
                    }
                    /* parse_heredoc_identifier calls nextc at least once */
                    pushback();
                }
                return tLSHIFT;
            } else if (bc == '=') {
                bc = nextc();
                if (bc == '>')
                    return tCMP;
                pushback();
                return tLEQ;
            }
            break;
        case '>':
            parser->expr_seen = 0;
            bc = nextc();
            if (bc == '>') {
                bc = nextc();
                if (bc == '=')
                    return tOP_ASGN;
                pushback();
                return tRSHIFT;
            }
            if (bc == '=')
                return tGEQ;
            break;
        case '!':
            bc = nextc();
            if (bc == '=') {
                parser->expr_seen = 0;
                return tNEQ;
            }
            if (bc == '~') {
                parser->expr_seen = 0;
                return tNMATCH;
            }
            tokp.end_line = parser->line;
            push_pos(parser, tokp);
            if (parser->def_seen && bc == '@')
                return '!';
            break;
        case '+':
            bc = nextc();
            if (bc == '=')
                return tOP_ASGN;
            tokp.end_line = parser->line;
            tokp.end_col = parser->column;
            if (!parser->expr_seen) {
                push_pos(parser, tokp);
                c = tUPLUS;
            } else if (parser->def_seen && bc == '@') {
                push_pos(parser, tokp);
                return tUPLUS;
            } else if (parser->expr_seen && space_seen && !isspace(bc)) {
                pushback();
                push_pos(parser, tokp);
                parser->expr_seen = 0;
                return tUPLUS;
            } else
                parser->expr_seen = 0;
            break;
        case '-':
            bc = nextc();
            if (bc == '=')
                return tOP_ASGN;
            tokp.end_line = parser->line;
            tokp.end_col = parser->column;
            if (bc == '>') {
                push_pos(parser, tokp);
                return tLAMBDA;
            }
            if (!parser->expr_seen) {
                push_pos(parser, tokp);
                c = tUMINUS;
            } else if (parser->def_seen && bc == '@') {
                push_pos(parser, tokp);
                return tUMINUS;
            } else if (parser->expr_seen && space_seen && !isspace(bc)) {
                pushback();
                push_pos(parser, tokp);
                parser->expr_seen = 0;
                return tUMINUS;
            } else
                parser->expr_seen = 0;
            break;
        case '*':
            bc = nextc();
            if (bc == '=')
                return tOP_ASGN;
            if (bc == '*') {
                bc = nextc();
                if (bc == '=') {
                    parser->expr_seen = 0;
                    return tOP_ASGN;
                }
                pushback();
                if (!parser->expr_seen)
                    return tDSTAR;
                parser->expr_seen = 0;
                return tPOW;
            }
            parser->auxiliar.start_line = parser->line;
            parser->auxiliar.start_col = parser->column - 2;
            if (!parser->expr_seen || parser->dot_seen)
                c = tSTAR;
            parser->expr_seen = 0;
            break;
        case '/':
            if (!parser->expr_seen) {
                tokp.start_line = parser->line;
                tokp.start_col = parser->column - 1;
                push_pos(parser, tokp);
                lex_strterm.term = c;
                lex_strterm.can_embed = 1;
                lex_strterm.token = token_regexp;
                return tSTRING_BEG;
            }
            parser->expr_seen = 0;
            bc = nextc();
            if (bc == '=')
                return tOP_ASGN;
            break;
        case '%':
            bc = nextc();
            if (bc == '=')
                return tOP_ASGN;
            if (is_shortcut(bc)) {
                /* TODO: is_shortcut can be simplified I think */
                tokp.start_line = parser->line;
                tokp.start_col = parser->column - 2;
                push_pos(parser, tokp);
                lex_strterm.token = guess_kind(parser, bc);
                if (isalpha(bc))
                    bc = nextc();
                lex_strterm.term = closing_char(bc);
                lex_strterm.can_embed = 1;
                return tSTRING_BEG;
            }
            parser->expr_seen = 0;
            break;
        case '&':
            bc = nextc();
            if (bc == '&') {
                parser->expr_seen = 0;
                bc = nextc();
                if (bc == '=')
                    return tOP_ASGN;
                pushback();
                return tAND;
            }
            if (bc == '=') {
                parser->expr_seen = 0;
                return tOP_ASGN;
            }
            if (!parser->expr_seen || parser->dot_seen)
                c = tAMPER;
            parser->expr_seen = 0;
            break;
        case '|':
            bc = nextc();
            parser->expr_seen = 0;
            if (bc == '|') {
                bc = nextc();
                if (bc == '=')
                    return tOP_ASGN;
                return tOR;
            }
            if (bc == '=')
                return tOP_ASGN;
            break;
        case '.':
            bc = nextc();
            if (bc == '.') {
                parser->expr_seen = 0;
                bc = nextc();
                if (bc == '.')
                    return tDOT3;
                pushback();
                return tDOT2;
            }
            parser->dot_seen = 1;
            break;
        case ':':
            bc = nextc();
            if (bc == ':') {
                if (!parser->expr_seen || (parser->expr_seen && space_seen))
                    return tCOLON3;
                parser->dot_seen = 1;
                return tCOLON2;
            }
            if (!isspace(bc)) {
                pushback();
                parser->symbeg = 1;
                parser->expr_seen = 1;
                push_pos(parser, tokp);
                return tSYMBEG;
            }
            parser->expr_seen = 0;
            break;
        case '^':
            bc = nextc();
            if (bc == '=') {
                parser->expr_seen = 0;
                return tOP_ASGN;
            }
            pushback();
        case ';':
        case ',':
            parser->expr_seen = 0;
            return c;
        case '?':
            bc = nextc();
            if (!isspace(bc)) {
                if (!parser->expr_seen) {
                    if (bc == '\\')
                        nextc();
                    tokp.end_line = parser->line;
                    tokp.end_col = parser->column;
                    push_pos(parser, tokp);
                    parser->expr_seen = 1;
                    return tCHAR;
                }
            }
            parser->expr_seen = 0;
            break;
        case '`':
            if (parser->def_seen)
                return c;
            /* fallthrough */
        case '"':
            space_seen = 1;
            /* fallthrough */
        case '\'':
            lex_strterm.term = c;
            lex_strterm.can_embed = space_seen;
            lex_strterm.token = token_string;
            push_pos(parser, tokp);
            return tSTRING_BEG;
        case '\\':
            c = nextc();
            if (c == '\n') {
                space_seen = 1;
                goto retry;
            }
            pushback();
            return '\\';
        case '(':
            parser->paren_nest++;
            if (parser->special_arg) {
                COND_PUSH(0);
                CMDARG_PUSH(0);
                parser->special_arg = 0;
            } else if (!parser->expr_seen || COND_P())
                c = tLPAREN;
            else {
                COND_PUSH(0);
                CMDARG_PUSH(0);
            }
            return c;
        case ')':
            parser->paren_nest--;
            parser->expr_seen = 1;
            CMDARG_LEXPOP();
            COND_LEXPOP();
            if (!parser->paren_nest)
                parser->mcall = 0;
            return c;
        case '{':
            push_pos(parser, tokp);
            if (parser->lpar_beg && parser->lpar_beg == parser->paren_nest) {
                parser->lpar_beg = 0;
                parser->paren_nest--;
                COND_PUSH(0);
                CMDARG_PUSH(0);
                parser->expr_seen = 0;
                if (parser->version < ruby19) {
                    yywarning("\"->\" syntax is only available in Ruby 1.9.x or higher.");
                }
                return tLAMBEG; /* this is a lambda ->() {} construction */
            }
            if (!parser->expr_seen || COND_P())
                c = tLBRACE; /* smells like hash */
            else if (parser->brace_arg)
                c = tLBRACE_ARG; /* block (expr) */
            parser->expr_seen = 0;
            COND_PUSH(0);
            CMDARG_PUSH(0);
            return c; /* block (primary) */
        case '}':
            parser->expr_seen = 1;
            parser->brace_arg = 1;
            CMDARG_LEXPOP();
            COND_LEXPOP();
            tokp.end_line = parser->line;
            tokp.end_col = parser->column;
            push_pos(parser, tokp);
            return c;
        case '@':
            cp = lexbuf;
            *cp++ = c;
            c = nextc();
            if (c != '@') {
                bc = IVAR;
            } else {
                *cp++ = c;
                c = nextc();
                bc = CVAR;
            }
            parser->expr_seen = 1;
            parser->dot_seen = 0;
            goto talpha;
        case '$':
            tokp.end_line = parser->line;
            parser->expr_seen = 1;
            parser->dot_seen = 0;
            cp = lexbuf;
            *cp++ = c;
            bc = nextc();
            switch (bc) {
                case '1': case '2': case '3': case '4':
                case '5': case '6': case '7': case '8': case '9':
                    c = bc;
                    while (isdigit(c)) {
                        *cp++ = c;
                        c = nextc();
                    }
                    *cp = '\0';
                    pushback();
                    c = tNTH_REF;
                    break;
                case '~': case '*': case '$': case '?': case '!': case '@':
                case '/': case '\\': case ';': case ',': case '.': case '=':
                case ':': case '<': case '>': case '\"':
                case '&': case '`': case '\'': case '+':
                case '0':
                    c = GLOBAL;
                    *cp++ = bc;
                    *cp = '\0';
                    break;
                case '-':
                    c = nextc();
                    *cp++ = bc;
                    bc = GLOBAL;
                    goto talpha;
                default:
                    c = bc;
                    bc = GLOBAL;
                    goto talpha;
            }
            tokp.end_col = parser->column;
            push_pos(parser, tokp);
            push_stack(parser, lexbuf);
            return c;
        case '~':
            bc = nextc();
            push_pos(parser, tokp);
            if (parser->def_seen && bc == '@') {
                tokp.end_col = parser->column;
                return c;
            }
            break;
        default:
            cp = lexbuf;
            goto talpha;
    }
    pushback();
    return c;

talpha:
    {
        int step = 0;
        int ax = 0;
        int last_col = 0;

        while (not_sep(parser->lex_prev)) {
            step = utf8_charsize(parser->lex_prev);
            ax += step - 1;
            while (step-- > 0) {
                *cp++ = c;
                last_col = parser->column;
                c = nextc();
            }
            if (c < 0) {
                parser->eof_reached = 1;
                break;
            }
        }
        switch (c) {
        case '=':
            if (!parser->def_seen && !parser->symbeg && !parser->in_alias)
                break;
            if (*(parser->lex_p) == '>')
                break;
        case '!': case '?':
            *cp++ = c;
            last_col = parser->column;
            c = nextc();
        }
        if (parser->def_seen && (isspace(c) || c == '('))
            parser->def_seen = 0;
        *cp = '\0';
        parser->column -= ax;
        tokp.end_line = tokp.start_line;
        tokp.end_col = last_col - ax;
        push_pos(parser, tokp);
        pushback();

        /* IVAR, CVAR, GLOBAL */
        if (bc > 0) {
            push_stack(parser, lexbuf);
            return bc;
        }

        /* TODO: I'm sure this can be reduced ! */
        if (c == '(') {
            push_stack(parser, lexbuf);
            parser->expr_seen = 0;
            parser->special_arg = 1;
            parser->mcall = 1;
            parser->dot_seen = 0;
            return BASE;
        } else if (parser->dot_seen) {
            push_stack(parser, lexbuf);
            parser->dot_seen = 0;
            parser->expr_seen = 1;
            return (is_upper(lexbuf[0])) ? CONST : BASE;
        }

        /* TODO: Oh Lord if it can be reduced ... */
        parser->dot_seen = 0;
        const struct kwtable *kw = rb_reserved_word(lexbuf, cp - lexbuf);
        if (kw) {
            c = kw->id[0];
            switch (c) {
                case tDEF:
                    parser->def_seen = 1;
                case tMODULE: case tCLASS:
                    push_last_comment(parser);
                    break;
                case tALIAS:
                    parser->in_alias = 1;
                    break;
                case tEND:
                    CMDARG_PUSH(0);
                    break;
                case tRETURN:
                    parser->expr_mid = 2;
            }
            if (c != kw->id[1] && (parser->expr_seen || parser->expr_mid > 0)) {
                c = kw->id[1];
                parser->expr_seen = 0;
            } else
                parser->expr_seen = kw->expr;
            bc = nextc();
            if (c == ':' && bc != ':') {
                parser->expr_seen = 0;
                return tKEY;
            }
            pushback();
            /* TODO: will be removed in the future */
            if (c == tDO) {
                if (parser->lpar_beg && parser->lpar_beg == parser->paren_nest) {
                    parser->lpar_beg = 0;
                    parser->paren_nest--;
                    c = tDO_LAMBDA;
                } else if (COND_P()) {
                    c = tDO_COND;
                } else if (CMDARG_P() || !parser->expr_seen || parser->brace_arg) {
                    CMDARG_PUSH(0);
                    c = tDO_BLOCK;
                } else
                    c = tDO;
                parser->expr_seen = 0;
            }
            return c;
        }
        if (is_special_method(lexbuf)) {
            if (!strcmp(lexbuf, "__END__")) {
                parser->eof_reached = 1;
                return tpEND;
            }
            push_stack(parser, lexbuf);
            return BASE;
        }
        parser->expr_seen = 1;
        push_stack(parser, lexbuf);
        if (is_upper(lexbuf[0]))
            return CONST;
        nextc();
        if (c == ':' && *(parser->lex_p) != ':') {
            parser->expr_seen = 0;
            return tKEY;
        }
        pushback();
        return BASE;
    }

tnum:
    /* TODO Can be optimized */
    /* TODO: maybe then it could be embedded into the switch, with less crap going on */
    {
        char hex, bin, has_point, aux;
        hex = bin = has_point = aux = 0;

        if (c == '0') {
            bc = nextc();
            if (to_upper(bc) == 'X') {
                hex = 1;
                c = nextc();
            } else if (to_upper(bc) == 'B') {
                bin = 1;
                c = nextc();
            }
            pushback();
        }
        while (c > 0 && ((isdigit(c) && !bin) || (!hex && !bin && !has_point && c == '.')
                    || (hex && to_upper(c) >= 'A' && to_upper(c) < 'G')
                    || (bin && (c == '1' || c == '0')) || c == '_')) {
            if (c == '.') {
                if (!isdigit(*parser->lex_p)) {
                    tokp.end_line = parser->line;
                    tokp.end_col = parser->column - 1;
                    push_pos(parser, tokp);
                    pushback();
                    return NUMERIC;
                }
                has_point = 1;
            }
            aux = 1;
            c = nextc();
        }
        if ((bin || hex) && !aux)
            yyerror(parser, "numeric literal without digits");

        /* is it an exponential number ? */
        if (!bin && !hex && to_upper(c) == 'E') {
            c = nextc();
            if (isdigit(c) || ((c == '+' || c == '-') && isdigit(*(parser->lex_p))))
                c = nextc();
            while (c != -1 && isdigit(c))
                c = nextc();
        }

        parser->expr_seen = 1;
        parser->dot_seen = 0;
        if (c != -1)
            pushback();
        tokp.end_line = parser->line;
        tokp.end_col = parser->column;
        push_pos(parser, tokp);
        return (has_point) ? FLOAT : NUMERIC;
    }
}

/* Standard yylex. */
static int yylex(void *lval, void *p)
{
    struct parser_t * parser = (struct parser_t *) p;
    int t = token_invalid;
    _unused_(lval);

    t = parser_yylex(parser);

    /* TODO: maybe we can get rid of these guys */

    /* Unset some flags if necessary */
    if (parser->brace_arg && t != '}' && t != ']')
        parser->brace_arg = 0;
    if (t == tOP_ASGN || t == '=')
        parser->expr_seen = 0;
    parser->expr_mid--;
    if (parser->symbeg && t != tSYMBEG) {
        parser->symbeg = 0;
        parser->expr_seen = 1;
    }

    /* TODO: to be removed */
    if (!t)
        parser->eof_reached = 1;
    return t;
}

/*
 * Error handling. Take the formmated string s and append the error
 * string to the list of errors p->errors.
 */
static void yyerror(struct parser_t *parser, const char *s)
{
    struct error_t *e = (struct error_t *) malloc(sizeof(struct error_t));

    e->msg = strdup(s);
    e->line = parser->line;
    e->column = parser->column;
    e->warning = parser->warning;
    e->next = e;
    if (parser->errors)
        parser->last_error->next = e;
    else
        parser->errors = e;
    parser->last_error = e;
    parser->last_error->next = NULL;

    parser->eof_reached = !e->warning;
    parser->unrecoverable = !e->warning;
}

struct ast_t * rb_compile_file(struct options_t *opts)
{
    struct parser_t p;
    struct ast_t *result;

    /* Initialize parser */
    init_parser(&p);
    p.name = opts->path;
    p.version = opts->version;
    if (!opts->contents) {
        if (!retrieve_source(&p, opts->path))
            return NULL;
    } else {
        p.content_given = 1;
        p.length = strlen(opts->contents);
        p.blob = opts->contents;
        p.lex_p = opts->contents;
    }

    /* Let's parse */
    result = (struct ast_t *) malloc(sizeof(struct ast_t));
    result->tree = NULL;
    result->unrecoverable = 1;
    for (;;) {
        yyparse(&p);
        if (p.ast != NULL) {
            if (result->tree == NULL)
                result->tree = p.ast;
            else
                update_list(result->tree, p.ast);
        }
        if (p.eof_reached) {
            result->errors = p.errors;
            result->unrecoverable = p.unrecoverable;
            break;
        }
    }
    free_parser(&p);

    return result;
}

#ifdef BUILD_TESTS
/*
 * Compile a file like the rb_compile_file function but printing
 * things directly to the stdout. This function is used for the tests.
 */
int rb_debug_file(struct options_t *opts)
{
    struct parser_t p;
    int index;

    /* Set up parser */
    init_parser(&p);
    p.name = strdup(opts->path);
    p.version = opts->version;
    if (!retrieve_source(&p, p.name))
        return 0;

    printf("Resulting AST's:");
    for (;;) {
        printf("\n");
        yyparse(&p);
        print_node(p.ast);
        if (p.ast != NULL) {
            if (p.ast->cond != NULL) {
                printf("\nCondition: ");
                print_node(p.ast->cond);
            }
            if (p.ast->l != NULL && p.ast->l->ensure != NULL) {
                if (p.ast->l->cond != NULL) {
                    printf("\nCondition: ");
                    print_node(p.ast->l->cond);
                }
                printf("\nEnsure: ");
                print_node(p.ast->l->ensure);
            }
            free_ast(p.ast);
            p.ast = NULL;
        }
        if (p.eof_reached) {
            if (p.errors)
                print_errors(p.errors);
            break;
        }
    }

    /* Check that all the stacks are empty */
    for (index = 0; index < p.sp; index++)
        printf("\nS: %s", p.stack[index]);
    printf("\n");

    for (index = 0; index < p.pos_size; index++)
        printf("\nP: %i:%i", p.pos_stack[index].start_line, p.pos_stack[index].start_col);
    printf("\n");
    free_parser(&p);
    return 1;
}
#endif
