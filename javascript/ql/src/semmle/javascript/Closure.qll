/**
 * Provides classes for working with the Closure-Library module system.
 */

import javascript

module Closure {
  /**
   * A reference to a Closure namespace.
   */
  class ClosureNamespaceRef extends DataFlow::Node {
    ClosureNamespaceRef::Range range;

    ClosureNamespaceRef() { this = range }

    /**
     * Gets the namespace being referenced.
     */
    string getClosureNamespace() { result = range.getClosureNamespace() }
  }

  module ClosureNamespaceRef {
    /**
     * A reference to a Closure namespace.
     *
     * Can be subclassed to classify additional nodes as namespace references.
     */
    abstract class Range extends DataFlow::Node {
      /**
       * Gets the namespace being referenced.
       */
      abstract string getClosureNamespace();
    }
  }

  /**
   * A data flow node that returns the value of a closure namespace.
   */
  class ClosureNamespaceAccess extends ClosureNamespaceRef {
    override ClosureNamespaceAccess::Range range;
  }

  module ClosureNamespaceAccess {
    /**
     * A data flow node that returns the value of a closure namespace.
     *
     * Can be subclassed to classify additional nodes as namespace accesses.
     */
    abstract class Range extends ClosureNamespaceRef::Range { }
  }

  /**
   * A call to a method on the `goog.` namespace, as a closure reference.
   */
  abstract private class DefaultNamespaceRef extends DataFlow::MethodCallNode,
    ClosureNamespaceRef::Range {
    DefaultNamespaceRef() { this = DataFlow::globalVarRef("goog").getAMethodCall() }

    override string getClosureNamespace() { result = getArgument(0).asExpr().getStringValue() }
  }

  /**
   * Holds if `node` is the data flow node corresponding to the expression in
   * a top-level expression statement.
   */
  private predicate isTopLevelExpr(DataFlow::Node node) {
    any(TopLevel tl).getAChildStmt().(ExprStmt).getExpr().flow() = node
  }

  /**
   * A top-level call to `goog.provide`.
   */
  private class DefaultClosureProvideCall extends DefaultNamespaceRef {
    DefaultClosureProvideCall() {
      getMethodName() = "provide" and
      isTopLevelExpr(this)
    }
  }

  /**
   * A top-level call to `goog.provide`.
   */
  class ClosureProvideCall extends ClosureNamespaceRef, DataFlow::MethodCallNode {
    override DefaultClosureProvideCall range;
  }

  /**
   * A call to `goog.require`.
   */
  private class DefaultClosureRequireCall extends DefaultNamespaceRef, ClosureNamespaceAccess::Range {
    DefaultClosureRequireCall() { getMethodName() = "require" }
  }

  /**
   * A call to `goog.require`.
   */
  class ClosureRequireCall extends ClosureNamespaceAccess, DataFlow::MethodCallNode {
    override DefaultClosureRequireCall range;
  }

  /**
   * A top-level call to `goog.module` or `goog.declareModuleId`.
   */
  private class DefaultClosureModuleDeclaration extends DefaultNamespaceRef {
    DefaultClosureModuleDeclaration() {
      (getMethodName() = "module" or getMethodName() = "declareModuleId") and
      isTopLevelExpr(this)
    }
  }

  /**
   * A top-level call to `goog.module` or `goog.declareModuleId`.
   */
  class ClosureModuleDeclaration extends ClosureNamespaceRef, DataFlow::MethodCallNode {
    override DefaultClosureModuleDeclaration range;
  }

  /**
   * A module using the Closure module system, declared using `goog.module()` or `goog.declareModuleId()`.
   */
  class ClosureModule extends Module {
    ClosureModule() {
      // Use AST-based predicate to cut recursive dependencies.
      exists(MethodCallExpr call |
        getAStmt().(ExprStmt).getExpr() = call and
        call.getReceiver().(GlobalVarAccess).getName() = "goog" and
        (call.getMethodName() = "module" or call.getMethodName() = "declareModuleId")
      )
    }

    /**
     * Gets the call to `goog.module` or `goog.declareModuleId` in this module.
     */
    ClosureModuleDeclaration getModuleDeclaration() { result.getTopLevel() = this }

    /**
     * Gets the namespace of this module.
     */
    string getClosureNamespace() { result = getModuleDeclaration().getClosureNamespace() }

    override Module getAnImportedModule() {
      exists(ClosureRequireCall imprt |
        imprt.getTopLevel() = this and
        result.(ClosureModule).getClosureNamespace() = imprt.getClosureNamespace()
      )
    }

    /**
     * Gets the top-level `exports` variable in this module, if this module is defined by
     * a `good.module` call.
     *
     * This variable denotes the object exported from this module.
     *
     * Has no result for ES6 modules using `goog.declareModuleId`.
     */
    Variable getExportsVariable() {
      getModuleDeclaration().getMethodName() = "module" and
      result = getScope().getVariable("exports")
    }

    override predicate exports(string name, ASTNode export) {
      exists(DataFlow::PropWrite write, Expr base |
        write.getAstNode() = export and
        write.writes(base.flow(), name, _) and
        (
          base = getExportsVariable().getAReference()
          or
          base = getExportsVariable().getAnAssignedExpr()
        )
      )
    }
  }

  /**
   * A global Closure script, that is, a toplevel that is executed in the global scope and
   * contains a toplevel call to `goog.provide` or `goog.require`.
   */
  class ClosureScript extends TopLevel {
    ClosureScript() {
      not this instanceof ClosureModule and
      (
        any(ClosureProvideCall provide).getTopLevel() = this
        or
        any(ClosureRequireCall require).getTopLevel() = this
      )
    }

    /** Gets the identifier of a namespace required by this module. */
    string getARequiredNamespace() {
      exists(ClosureRequireCall require |
        require.getTopLevel() = this and
        result = require.getClosureNamespace()
      )
    }

    /** Gets the identifer of a namespace provided by this module. */
    string getAProvidedNamespace() {
      exists(ClosureProvideCall require |
        require.getTopLevel() = this and
        result = require.getClosureNamespace()
      )
    }
  }

  /**
   * Holds if `name` is a closure namespace, including proper namespace prefixes.
   */
  pragma[noinline]
  predicate isClosureNamespace(string name) {
    exists(string namespace | namespace = any(ClosureNamespaceRef ref).getClosureNamespace() |
      name = namespace.substring(0, namespace.indexOf("."))
      or
      name = namespace
    )
  }

  /**
   * Gets the closure namespace path addressed by the given data flow node, if any.
   */
  string getClosureNamespaceFromSourceNode(DataFlow::SourceNode node) {
    isClosureNamespace(result) and
    node = DataFlow::globalVarRef(result)
    or
    exists(DataFlow::SourceNode base, string basePath, string prop |
      basePath = getClosureNamespaceFromSourceNode(base) and
      node = base.getAPropertyRead(prop) and
      result = basePath + "." + prop and
      // ensure finiteness
      (
        isClosureNamespace(basePath)
        or
        // direct access, no indirection
        node.(DataFlow::PropRead).getBase() = base
      )
    )
    or
    // Associate an access path with the immediate RHS of a store on a closure namespace.
    // This is to support patterns like:
    // foo.bar = { baz() {} }
    exists(DataFlow::PropWrite write |
      node = write.getRhs() and
      result = getWrittenClosureNamespace(write)
    )
    or
    result = node.(ClosureNamespaceAccess).getClosureNamespace()
  }

  /**
   * Gets the closure namespace path written to by the given property write, if any.
   */
  string getWrittenClosureNamespace(DataFlow::PropWrite node) {
    result = getClosureNamespaceFromSourceNode(node.getBase().getALocalSource()) + "." +
        node.getPropertyName()
  }

  /**
   * Gets a data flow node that refers to the given value exported from a Closure module.
   */
  DataFlow::SourceNode moduleImport(string moduleName) {
    getClosureNamespaceFromSourceNode(result) = moduleName
  }
}
