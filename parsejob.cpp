/* This file is part of KDevelop
 *
 * Copyright 2008-2010 Alexander Dymo <adymo@kdevelop.org>
 * Copyright (C) 2011-2014 Miquel Sabaté Solà <mikisabate@gmail.com>
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

#include <mutex>

// Qt + KDE
#include <QReadLocker>

// KDevelop
#include <interfaces/ilanguage.h>
#include <interfaces/ilanguagecontroller.h>
#include <interfaces/icore.h>
#include <language/backgroundparser/backgroundparser.h>
#include <language/backgroundparser/urlparselock.h>
#include <language/duchain/duchainutils.h>

// Ruby
#include <debug.h>
#include <parsejob.h>
#include <languagesupport.h>
#include <parser/parser.h>
#include <duchain/builders/declarationbuilder.h>
#include <duchain/builders/usebuilder.h>
#include <duchain/editorintegrator.h>
#include <duchain/helpers.h>


using namespace KDevelop;
namespace ruby
{

ParseJob::ParseJob(const KDevelop::IndexedString &url, ILanguageSupport *languageSupport)
    : KDevelop::ParseJob(url, languageSupport)
    , m_parser (new Parser)
    , m_duContext (nullptr)
{
    /* There's nothing to do here. */
}

ParseJob::~ParseJob()
{
    delete m_parser;
}

LanguageSupport * ParseJob::ruby() const
{
    return dynamic_cast<LanguageSupport *>(languageSupport());
}

void ParseJob::run(ThreadWeaver::JobPointer pointer, ThreadWeaver::Thread *thread)
{
    Q_UNUSED(pointer);
    Q_UNUSED(thread);

    // Make sure that the builtins file is already loaded.
    if (document() != builtinsFile()) {
        const auto &langSupport = languageSupport();
        static std::once_flag once;

        std::call_once(once, [langSupport] {
            rDebug() << "Initializing internal function file" << builtinsFile();
            ParseJob internalJob(builtinsFile(), langSupport);
            internalJob.setMinimumFeatures(TopDUContext::AllDeclarationsAndContexts);
            internalJob.run({}, nullptr);
            Q_ASSERT(internalJob.success());
        });
    }

    UrlParseLock urlLock(document());
    if (!(minimumFeatures() & Rescheduled) &&
        !isUpdateRequired(languageString())) {
        return;
    }

    QReadLocker parseLock(ruby()->language()->parseLock());
    ProblemPointer p = readContents();
    if (p || abortRequested()) {
        return abortJob();
    }

    /*
     * NOTE: Although the parser can retrieve the contents on its own,
     * it's better to use contents().contents because this way the contents
     * are converted in utf8 format always.
     */
    m_parser->setContents(contents().contents);
    m_parser->setCurrentDocument(document());
    m_parser->setRubyVersion(ruby()->version());
    Ast *ast = m_parser->parse();

    /* Setting up the TopDUContext features */
    KDevelop::ReferencedTopDUContext toUpdate;
    {
        DUChainReadLocker lock;
        toUpdate = KDevelop::DUChainUtils::standardContextForUrl(document().toUrl());
    }

    KDevelop::TopDUContext::Features newFeatures = minimumFeatures();
    if (toUpdate) {
        newFeatures = (KDevelop::TopDUContext::Features)(newFeatures | toUpdate->features());
    }

    /* Remove update-flags like 'Recursive' or 'ForceUpdate' */
    newFeatures = static_cast<KDevelop::TopDUContext::Features>(newFeatures & KDevelop::TopDUContext::AllDeclarationsContextsUsesAndAST);

    /*
     * And finally we do all the work if parsing was successful. Otherwise,
     * we have to add a new problem
     */
    if (ast) {
        // Empty document, do nothing
        if (!ast->tree) {
            return;
        }
        if (abortRequested()) {
            m_parser->freeAst(ast);
            return abortJob();
        }

        EditorIntegrator editor;
        editor.setParseSession(m_parser);
        DeclarationBuilder builder(&editor);
        builder.setPriority(parsePriority());
        m_duContext = builder.build(editor.url(), ast, toUpdate);

        // Add warnings
        DUChainWriteLocker wlock;
        foreach (ProblemPointer p, m_parser->m_problems) {
            m_duContext->addProblem(p);
        }
        wlock.unlock();
        setDuChain(m_duContext);

        if (abortRequested()) {
            m_parser->freeAst(ast);
            return abortJob();
        }

        if (newFeatures & TopDUContext::AllDeclarationsContextsAndUses &&
            document() != builtinsFile()) {

            UseBuilder useBuilder(&editor);
            useBuilder.setPriority(parsePriority());
            useBuilder.buildUses(ast);
        }

        if (abortRequested()) {
            m_parser->freeAst(ast);
            return abortJob();
        }

        const QVector<IndexedString> unresolvedImports = builder.unresolvedImports();
        if (!unresolvedImports.isEmpty()) {
            // Check whether one of the imports is queued for parsing, this
            // is to avoid deadlocks
            bool dependencyInQueue = false;
            foreach (const IndexedString &url, unresolvedImports) {
                dependencyInQueue = KDevelop::ICore::self()->languageController()->backgroundParser()->isQueued(url);
                if (dependencyInQueue) {
                    break;
                }
            }

            // We check whether this document already has been re-scheduled
            // once and abort if that is the case. This prevents infinite
            // loops in case something goes wrong (optimally, shouldn't reach
            // here if the document was already rescheduled, but there's many
            // cases where this might still happen)
            if (!(minimumFeatures() & Rescheduled) && dependencyInQueue) {
                DUChainWriteLocker lock;
                KDevelop::ICore::self()->languageController()->backgroundParser()->addDocument(document(),
                                     static_cast<TopDUContext::Features>(TopDUContext::ForceUpdate | Rescheduled), parsePriority(),
                                     nullptr, ParseJob::FullSequentialProcessing);
            }
        }

        if (abortRequested()) {
            m_parser->freeAst(ast);
            return abortJob();
        }

        wlock.lock();
        m_duContext->setFeatures(newFeatures);
        KDevelop::ParsingEnvironmentFilePointer file = m_duContext->parsingEnvironmentFile();
        file->setModificationRevision(contents().modification);
        KDevelop::DUChain::self()->updateContextEnvironment(m_duContext, file.data());
        wlock.unlock();
        m_parser->freeAst(ast);

        highlightDUChain();
        rDebug() << "**** Parsing Succeeded ****";
    } else {
        rWarning() << "**** Parsing Failed ****";
        DUChainWriteLocker lock;
        m_duContext = DUChain::self()->chainForDocument(document());
        if (m_duContext) {
            m_duContext->parsingEnvironmentFile()->clearModificationRevisions();
            m_duContext->clearProblems();
        } else {
            ParsingEnvironmentFile *file = new ParsingEnvironmentFile(document());
            file->setLanguage(languageString());
            m_duContext = new TopDUContext(document(), RangeInRevision(0, 0, INT_MAX, INT_MAX), file);
            DUChain::self()->addDocumentChain(m_duContext);
        }

        foreach (ProblemPointer p, m_parser->m_problems) {
            rDebug() << "Added problem to context";
            m_duContext->addProblem(p);
        }
        setDuChain(m_duContext);
    }
}

}

