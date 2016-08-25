/*
 * This file is part of KDevelop
 * Copyright (C) 2012-2014 Miquel Sabaté Solà <mikisabate@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Library General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */


// KDE + KDevelop
#include <KLocalizedString>
#include <language/duchain/duchain.h>
#include <language/duchain/duchainlock.h>
#include <language/duchain/types/typeregister.h>
#include <language/util/kdevhash.h>

// Ruby
#include <duchain/helpers.h>
#include <duchain/types/classtype.h>


using namespace KDevelop;

namespace Ruby
{

REGISTER_TYPE(ClassType);

ClassType::ClassType() : KDevelop::StructureType(createData<ClassType>())
{
    /* There's nothing to do here */
}

ClassType::ClassType(const ClassType &rhs)
    : KDevelop::StructureType(copyData<ClassType>(*rhs.d_func()))
{
    /* There's nothing to do here */
}

ClassType::ClassType(ClassTypeData &data)
    : KDevelop::StructureType(data)
{
    /* There's nothing to do here */
}

void ClassType::addContentType(AbstractType::Ptr typeToAdd)
{
    if (!typeToAdd) // TODO: not sure :/
        return;
    AbstractType::Ptr type = mergeTypes(contentType().abstractType(), typeToAdd);
    d_func_dynamic()->m_contentType = IndexedType(type);
}

const IndexedType & ClassType::contentType() const
{
    return d_func()->m_contentType;
}

bool ClassType::isUseful() const
{
    // TODO: this is utter crap.
    return KDevelop::StructureType::toString() != "Object";
}

AbstractType * ClassType::clone() const
{
    return new ClassType(*this);
}

uint ClassType::hash() const
{
    return KDevHash(StructureType::hash()) <<
        ( contentType().abstractType() ? contentType().abstractType()->hash() : 0 );
}

bool ClassType::equals(const AbstractType *rhs) const
{
    if (!KDevelop::StructureType::equals(rhs)) {
        return false;
    }

    if (const ClassType *rhsClass = dynamic_cast<const ClassType *>(rhs)) {
        return rhsClass->contentType() == contentType();
    }
    return false;
}

QString ClassType::toString() const
{
    QString prefix = KDevelop::StructureType::toString();
    AbstractType::Ptr content = contentType().abstractType();
    return content ? i18n("%1 of %2", prefix, content->toString()) : prefix;
}

QString ClassType::containerToString() const
{
    return KDevelop::StructureType::toString();
}

} // End of namespace Ruby

