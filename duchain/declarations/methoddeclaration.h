/* This file is part of KDevelop
 *
 * Copyright (C) 2011  Miquel Sabaté <mikisabate@gmail.com>
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


#ifndef R_METHOD_DECLARATION_H
#define R_METHOD_DECLARATION_H


#include <language/duchain/functiondeclaration.h>
#include <duchain/duchainexport.h>


namespace Ruby
{

/**
 * @class MethodDeclarationData
 *
 * Private data structure for MethodDeclaration.
 */
class KDEVRUBYDUCHAIN_EXPORT MethodDeclarationData : public KDevelop::FunctionDeclarationData
{
public:
    /// Constructor.
    MethodDeclarationData()
        : KDevelop::FunctionDeclarationData(), classMethod(false)
    {
        /* There's nothing to do here */
    }

    /**
     * Copy constructor.
     * @param rhs data to copy.
     */
    MethodDeclarationData(const MethodDeclarationData &rhs)
        : KDevelop::FunctionDeclarationData(rhs)
    {
        classMethod = rhs.classMethod;
    }

    /// True if this is a Class method
    bool classMethod;
};

/**
 * @class MethodDeclaration
 *
 * In Ruby there are class methods (methods that belong to a class) and
 * instance methods (methods that belong to instances). This class stores
 * this information and, therefore, this is the one to be used instead
 * of the regular KDevelop::FunctionDeclaration.
 */
class KDEVRUBYDUCHAIN_EXPORT MethodDeclaration : public KDevelop::FunctionDeclaration
{
public:
    /**
     * Constructor.
     * @param range The range of this declaration.
     * @param ctx The context of this declaration.
     */
    MethodDeclaration(const KDevelop::RangeInRevision &range, KDevelop::DUContext *ctx);

    /// Copy constructor.
    MethodDeclaration(const MethodDeclaration &rhs);

    /**
     * Copy constructor.
     * @param data The data to be copied.
     */
    MethodDeclaration(MethodDeclarationData &data);

    /**
     * Set if this is a class or an instance method.
     * @param isClass True if this is a class method, false otherwise.
     */
    void setClassMethod(const bool isClass);

    /// @returns true if this is a class method, false otherwise.
    bool isClassMethod() const;

    enum { Identity = 42 /** The id of this Type. */ };

private:
    DUCHAIN_DECLARE_DATA(MethodDeclaration)
};

} // End of namespace Ruby


#endif /* R_METHOD_DECLARATION_H */
