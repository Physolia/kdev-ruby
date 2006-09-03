// THIS FILE IS GENERATED
// WARNING! All changes made in this file will be lost!

#ifndef ruby_SERIALIZATION_H_INCLUDED
#define ruby_SERIALIZATION_H_INCLUDED

#include "ruby_default_visitor.h"

#include <iostream>
#include <fstream>

namespace ruby
  {

  class serialize: public default_visitor
    {
    public:
      static void read(kdev_pg_memory_pool *p,
                       ast_node *node, std::ifstream *i)
      {
        serialize(p, node, i);
      }

      static void write(ast_node *node, std::ofstream *o)
      {
        serialize(node, o);
      }

    private:
      serialize(kdev_pg_memory_pool *p,
                ast_node *node, std::ifstream *i) : in(i), out(0)
      {
        memory_pool = p;
        if ( !node )
          node = create<program_ast>();
        visit_node( node );
      }

      serialize(ast_node *node, std::ofstream *o) : in(0), out(o)
      {
        visit_node( node );
      }

      std::ifstream *in;
      std::ofstream *out;

      // memory pool
      typedef kdev_pg_memory_pool memory_pool_type;
      kdev_pg_memory_pool *memory_pool;
      template <class T>
      inline T *create()
      {
        T *node = new (memory_pool->allocate(sizeof(T))) T();
        node->kind = T::KIND;
        return node;
      }
      template <class T, class E>
      void handle_list_node(const list_node<T> *t, E *e)
      {
        if (in)
          {
            bool b;
            in->read(reinterpret_cast<char*>(&b), sizeof(bool));
            if (b)
              {
                int count;
                in->read(reinterpret_cast<char*>(&count), sizeof(int));
                for ( int i = 0; i < count; ++i )
                  {
                    e = create<E>();
                    t = snoc(t, e, memory_pool);
                  }
              }
          }
        else if (out)
          {
            if (t)
              {
                bool b = true;
                out->write(reinterpret_cast<char*>(&b), sizeof(bool));
                int c = t->count();
                out->write(reinterpret_cast<char*>(&c), sizeof(int));
              }
            else
              {
                bool b = false;
                out->write(reinterpret_cast<char*>(&b), sizeof(bool));
              }

          }
      }

      template <class T>
      void handle_ast_node(T *t)
      {
        if (in)
          {
            bool b;
            in->read(reinterpret_cast<char*>(&b), sizeof(bool));
            if (b)
              {
                t = create<T>();
                in->read(reinterpret_cast<char*>(&t->start_token),
                         sizeof(std::size_t));
                in->read(reinterpret_cast<char*>(&t->end_token),
                         sizeof(std::size_t));
              }
          }
        else if (out)
          {
            if (t)
              {
                bool b = true;
                out->write(reinterpret_cast<char*>(&b), sizeof(bool));
                out->write(reinterpret_cast<char*>(&t->start_token),
                           sizeof(std::size_t));
                out->write(reinterpret_cast<char*>(&t->end_token),
                           sizeof(std::size_t));
              }
            else
              {
                bool b = false;
                out->write(reinterpret_cast<char*>(&b), sizeof(bool));
              }

          }
      }

      template <class T>
      void handle_variable(T *t)
      {
        if (in)
          {
            in->read( reinterpret_cast<char*>(t), sizeof(T));
          }
        else if (out)
          {
            out->write( reinterpret_cast<char*>(t), sizeof(T));
          }
      }

      virtual void visit_additiveExpression(additiveExpression_ast *node)
      {
        default_visitor::visit_additiveExpression(node);
      }

      virtual void visit_aliasParameter(aliasParameter_ast *node)
      {
        default_visitor::visit_aliasParameter(node);
      }

      virtual void visit_andExpression(andExpression_ast *node)
      {
        default_visitor::visit_andExpression(node);
      }

      virtual void visit_andorExpression(andorExpression_ast *node)
      {
        default_visitor::visit_andorExpression(node);
      }

      virtual void visit_arrayAccess(arrayAccess_ast *node)
      {
        default_visitor::visit_arrayAccess(node);
      }

      virtual void visit_arrayExpression(arrayExpression_ast *node)
      {
        default_visitor::visit_arrayExpression(node);
      }

      virtual void visit_arrayReferenceArgument(arrayReferenceArgument_ast *node)
      {
        handle_variable(&node->seen_star);
        default_visitor::visit_arrayReferenceArgument(node);
      }

      virtual void visit_assignmentExpression(assignmentExpression_ast *node)
      {
        default_visitor::visit_assignmentExpression(node);
      }

      virtual void visit_blockContent(blockContent_ast *node)
      {
        default_visitor::visit_blockContent(node);
      }

      virtual void visit_blockMethodDefinitionArgument(blockMethodDefinitionArgument_ast *node)
      {
        default_visitor::visit_blockMethodDefinitionArgument(node);
      }

      virtual void visit_blockMethodInvocationArgument(blockMethodInvocationArgument_ast *node)
      {
        default_visitor::visit_blockMethodInvocationArgument(node);
      }

      virtual void visit_block_var(block_var_ast *node)
      {
        handle_variable(&node->seen_star);
        default_visitor::visit_block_var(node);
      }

      virtual void visit_block_vars(block_vars_ast *node)
      {
        default_visitor::visit_block_vars(node);
      }

      virtual void visit_bodyStatement(bodyStatement_ast *node)
      {
        default_visitor::visit_bodyStatement(node);
      }

      virtual void visit_caseExpression(caseExpression_ast *node)
      {
        default_visitor::visit_caseExpression(node);
      }

      virtual void visit_classDefinition(classDefinition_ast *node)
      {
        default_visitor::visit_classDefinition(node);
      }

      virtual void visit_className(className_ast *node)
      {
        default_visitor::visit_className(node);
      }

      virtual void visit_codeBlock(codeBlock_ast *node)
      {
        default_visitor::visit_codeBlock(node);
      }

      virtual void visit_colonAccess(colonAccess_ast *node)
      {
        default_visitor::visit_colonAccess(node);
      }

      virtual void visit_command(command_ast *node)
      {
        default_visitor::visit_command(node);
      }

      virtual void visit_commandOutput(commandOutput_ast *node)
      {
        default_visitor::visit_commandOutput(node);
      }

      virtual void visit_compoundStatement(compoundStatement_ast *node)
      {
        default_visitor::visit_compoundStatement(node);
      }

      virtual void visit_doOrTerminalOrColon(doOrTerminalOrColon_ast *node)
      {
        default_visitor::visit_doOrTerminalOrColon(node);
      }

      virtual void visit_dotAccess(dotAccess_ast *node)
      {
        default_visitor::visit_dotAccess(node);
      }

      virtual void visit_elementReference(elementReference_ast *node)
      {
        default_visitor::visit_elementReference(node);
      }

      virtual void visit_equalityExpression(equalityExpression_ast *node)
      {
        default_visitor::visit_equalityExpression(node);
      }

      virtual void visit_exceptionHandlingExpression(exceptionHandlingExpression_ast *node)
      {
        default_visitor::visit_exceptionHandlingExpression(node);
      }

      virtual void visit_exceptionList(exceptionList_ast *node)
      {
        default_visitor::visit_exceptionList(node);
      }

      virtual void visit_expression(expression_ast *node)
      {
        default_visitor::visit_expression(node);
      }

      virtual void visit_expressionSubstitution(expressionSubstitution_ast *node)
      {
        default_visitor::visit_expressionSubstitution(node);
      }

      virtual void visit_forExpression(forExpression_ast *node)
      {
        default_visitor::visit_forExpression(node);
      }

      virtual void visit_hashExpression(hashExpression_ast *node)
      {
        default_visitor::visit_hashExpression(node);
      }

      virtual void visit_ifExpression(ifExpression_ast *node)
      {
        default_visitor::visit_ifExpression(node);
      }

      virtual void visit_keyValuePair(keyValuePair_ast *node)
      {
        default_visitor::visit_keyValuePair(node);
      }

      virtual void visit_keyword(keyword_ast *node)
      {
        default_visitor::visit_keyword(node);
      }

      virtual void visit_keywordAsMethodName(keywordAsMethodName_ast *node)
      {
        default_visitor::visit_keywordAsMethodName(node);
      }

      virtual void visit_literal(literal_ast *node)
      {
        default_visitor::visit_literal(node);
      }

      virtual void visit_logicalAndExpression(logicalAndExpression_ast *node)
      {
        default_visitor::visit_logicalAndExpression(node);
      }

      virtual void visit_logicalOrExpression(logicalOrExpression_ast *node)
      {
        default_visitor::visit_logicalOrExpression(node);
      }

      virtual void visit_methodCall(methodCall_ast *node)
      {
        default_visitor::visit_methodCall(node);
      }

      virtual void visit_methodDefinition(methodDefinition_ast *node)
      {
        default_visitor::visit_methodDefinition(node);
      }

      virtual void visit_methodDefinitionArgument(methodDefinitionArgument_ast *node)
      {
        default_visitor::visit_methodDefinitionArgument(node);
      }

      virtual void visit_methodDefinitionArgumentWithoutParen(methodDefinitionArgumentWithoutParen_ast *node)
      {
        default_visitor::visit_methodDefinitionArgumentWithoutParen(node);
      }

      virtual void visit_methodInvocationArgumentWithParen(methodInvocationArgumentWithParen_ast *node)
      {
        default_visitor::visit_methodInvocationArgumentWithParen(node);
      }

      virtual void visit_methodInvocationArgumentWithoutParen(methodInvocationArgumentWithoutParen_ast *node)
      {
        default_visitor::visit_methodInvocationArgumentWithoutParen(node);
      }

      virtual void visit_methodName(methodName_ast *node)
      {
        default_visitor::visit_methodName(node);
      }

      virtual void visit_methodNameSupplement(methodNameSupplement_ast *node)
      {
        default_visitor::visit_methodNameSupplement(node);
      }

      virtual void visit_mlhs_item(mlhs_item_ast *node)
      {
        default_visitor::visit_mlhs_item(node);
      }

      virtual void visit_moduleDefinition(moduleDefinition_ast *node)
      {
        default_visitor::visit_moduleDefinition(node);
      }

      virtual void visit_moduleName(moduleName_ast *node)
      {
        default_visitor::visit_moduleName(node);
      }

      virtual void visit_mrhs(mrhs_ast *node)
      {
        handle_variable(&node->seen_star);
        default_visitor::visit_mrhs(node);
      }

      virtual void visit_multiplicativeExpression(multiplicativeExpression_ast *node)
      {
        default_visitor::visit_multiplicativeExpression(node);
      }

      virtual void visit_normalMethodDefinitionArgument(normalMethodDefinitionArgument_ast *node)
      {
        default_visitor::visit_normalMethodDefinitionArgument(node);
      }

      virtual void visit_normalMethodInvocationArgument(normalMethodInvocationArgument_ast *node)
      {
        default_visitor::visit_normalMethodInvocationArgument(node);
      }

      virtual void visit_notExpression(notExpression_ast *node)
      {
        default_visitor::visit_notExpression(node);
      }

      virtual void visit_numeric(numeric_ast *node)
      {
        default_visitor::visit_numeric(node);
      }

      virtual void visit_operatorAsMethodname(operatorAsMethodname_ast *node)
      {
        default_visitor::visit_operatorAsMethodname(node);
      }

      virtual void visit_orExpression(orExpression_ast *node)
      {
        default_visitor::visit_orExpression(node);
      }

      virtual void visit_parallelAssignmentLeftOver(parallelAssignmentLeftOver_ast *node)
      {
        handle_variable(&node->seen_star);
        default_visitor::visit_parallelAssignmentLeftOver(node);
      }

      virtual void visit_powerExpression(powerExpression_ast *node)
      {
        default_visitor::visit_powerExpression(node);
      }

      virtual void visit_predefinedValue(predefinedValue_ast *node)
      {
        default_visitor::visit_predefinedValue(node);
      }

      virtual void visit_primaryExpression(primaryExpression_ast *node)
      {
        default_visitor::visit_primaryExpression(node);
      }

      virtual void visit_program(program_ast *node)
      {
        default_visitor::visit_program(node);
      }

      virtual void visit_rangeExpression(rangeExpression_ast *node)
      {
        default_visitor::visit_rangeExpression(node);
      }

      virtual void visit_regex(regex_ast *node)
      {
        default_visitor::visit_regex(node);
      }

      virtual void visit_relationalExpression(relationalExpression_ast *node)
      {
        default_visitor::visit_relationalExpression(node);
      }

      virtual void visit_restMethodDefinitionArgument(restMethodDefinitionArgument_ast *node)
      {
        default_visitor::visit_restMethodDefinitionArgument(node);
      }

      virtual void visit_restMethodInvocationArgument(restMethodInvocationArgument_ast *node)
      {
        default_visitor::visit_restMethodInvocationArgument(node);
      }

      virtual void visit_shiftExpression(shiftExpression_ast *node)
      {
        default_visitor::visit_shiftExpression(node);
      }

      virtual void visit_statement(statement_ast *node)
      {
        default_visitor::visit_statement(node);
      }

      virtual void visit_statementWithoutModifier(statementWithoutModifier_ast *node)
      {
        default_visitor::visit_statementWithoutModifier(node);
      }

      virtual void visit_statements(statements_ast *node)
      {
        default_visitor::visit_statements(node);
      }

      virtual void visit_string(string_ast *node)
      {
        default_visitor::visit_string(node);
      }

      virtual void visit_symbol(symbol_ast *node)
      {
        default_visitor::visit_symbol(node);
      }

      virtual void visit_terminal(terminal_ast *node)
      {
        default_visitor::visit_terminal(node);
      }

      virtual void visit_ternaryIfThenElseExpression(ternaryIfThenElseExpression_ast *node)
      {
        default_visitor::visit_ternaryIfThenElseExpression(node);
      }

      virtual void visit_thenOrTerminalOrColon(thenOrTerminalOrColon_ast *node)
      {
        default_visitor::visit_thenOrTerminalOrColon(node);
      }

      virtual void visit_unaryExpression(unaryExpression_ast *node)
      {
        default_visitor::visit_unaryExpression(node);
      }

      virtual void visit_undefParameter(undefParameter_ast *node)
      {
        default_visitor::visit_undefParameter(node);
      }

      virtual void visit_unlessExpression(unlessExpression_ast *node)
      {
        default_visitor::visit_unlessExpression(node);
      }

      virtual void visit_untilExpression(untilExpression_ast *node)
      {
        default_visitor::visit_untilExpression(node);
      }

      virtual void visit_variable(variable_ast *node)
      {
        default_visitor::visit_variable(node);
      }

      virtual void visit_whileExpression(whileExpression_ast *node)
      {
        default_visitor::visit_whileExpression(node);
      }

    };

} // end of namespace ruby

#endif


