// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart' as dart;

import 'ast.dart' as java;
import 'visitor.dart' as java;
import 'types.dart' as java;
import 'constants.dart';
import '../compiler/compiler_state.dart';
import '../compiler/runner.dart' show CompileErrorException;

/// Builds a Java class that contains the top-level procedures and fields in
/// a Dart [Library].
java.ClassDecl buildWrapperClass(
    dart.Library library, CompilerState compilerState) {
  var type = compilerState.getTopLevelClass(library);
  java.ClassDecl result =
      new java.ClassDecl(type, supertype: java.JavaType.object);

  var instance = new _JavaAstBuilder(compilerState);
  result.fields = library.fields.map(instance.visitField).toList();
  result.methods = library.procedures.map(instance.visitProcedure).toList();

  return result;
}

/// Builds a Java class AST from a kernel class AST. Kernel does not give names
/// to temporary variables, so we need to keep track of them manually. Also see
/// the comment for visitLet.
List<java.ClassDecl> buildClass(dart.Class node, CompilerState compilerState) {
  // Nothing to do for core abstract classes like `int`.
  if (compilerState.isJavaClass(node)) {
    return const <java.ClassDecl>[];
  }

  return [node.accept(new _JavaAstBuilder(compilerState))];
}

/// A temporary local variable defined in a method.
class TemporaryVariable {
  String name;

  dart.DartType type;

  TemporaryVariable(this.name, this.type);
}

/// A container for a delegator (actual Java constructor) and an instance
/// method whose body contains the Dart constructor.
/// 
/// See also comment of `buildConstructor`
class _JavaConstructor {
  final java.Constructor delegator;

  final java.MethodDef body;

  _JavaConstructor(this.delegator, this.body);
}

/// Builds a Java class from Dart IR.
class _JavaAstBuilder extends dart.Visitor<java.Node> {
  _JavaAstBuilder(this.compilerState);

  /// A reference to the [dart.Class] that is being visited.
  ///
  /// This must be [:null:] before [visitNormalClass] is called, and may be null
  /// afterwards. If it is not [:null:] before calling [visitNormalClass], then
  /// this builder assumes that it is being reused, and throws an error. If it
  /// is [:null:] while building a [dart.Member], then that [dart.Member] is a
  /// top-level field or function in a [dart.Library].
  ///
  /// This reference is used to compute the [dart.DartType] of [:this:] inside
  /// of method definitions.
  dart.Class thisDartClass;

  /// A counter for generating unique identifiers for temporary variables.
  int tempVarCounter = 0;

  /// A map assigning Kernel AST variables to temporary variables.
  Map<dart.VariableDeclaration, TemporaryVariable> tempVars = null;

  /// Generates a unique variable identifier.
  String nextTempVarIdentifier() {
    return "__tempVar_${tempVarCounter++}";
  }

  final CompilerState compilerState;

  /// Default visitor method. Useful to track which AST nodes are not
  /// translated yet.
  @override
  java.Node defaultExpression(dart.Expression node) {
    print("WARNING: java_builder does not handle ${node.runtimeType} yet");
    return null;
  }

  /// Default visitor method. Useful to track which AST nodes are not
  /// translated yet.
  @override
  java.Node defaultStatement(dart.Statement node) {
    print("WARNING: java_builder does not handle ${node.runtimeType} yet");
    return null;
  }

  /// Visits a non-mixin class.
  @override
  java.ClassDecl visitNormalClass(dart.NormalClass node) {
    assert(thisDartClass == null);
    thisDartClass = node;
    java.ClassOrInterfaceType type = compilerState.getClass(node);
    List<java.FieldDecl> fields = node.fields.map(buildClassField).toList();
    List<java.MethodDef> implicitGetters = 
      node.fields.map(this.buildGetter).toList();
    List<java.MethodDef> implicitSetters = node.fields.where((f) => !f.isFinal)
        .map(this.buildSetter).toList();
    List<java.MethodDef> methods =
        node.procedures.map(this.visitProcedure).toList();

    List<_JavaConstructor> constructors = 
        node.constructors.map((c) => 
          this.buildConstructor(c, node.fields)).toList();
    List<java.Constructor> constructorDelegators = constructors.map((c) =>
      c.delegator).toList();
    methods.insertAll(0, constructors.map((c) => c.body));

    // Add empty constructor (for implementing Dart constructor semantics)
    constructorDelegators.add(buildEmptyConstructor(type));

    // Merge getters/setters
    if (methods.any((m) => implicitGetters.any((g) => m.name == g.name))) {
      // This can happen because we simple prepend getters with "get"
      throw new CompileErrorException("Name clash between getter and method");
    }
    if (methods.any((m) => implicitSetters.any((s) => m.name == s.name))) {
      // This can happen because we simple prepend getters with "set"
      throw new CompileErrorException("Name clash between setter and method");
    }
    methods.addAll(implicitGetters);
    methods.addAll(implicitSetters);

    java.ClassOrInterfaceType supertype = node.supertype.accept(this);
    if (supertype == java.JavaType.object) {
      // Make sure that "extends Object" results in "extends DartObject"
      // TODO(springerm): Remove hard-coded special case once we 
      // figure out interop
      supertype = java.JavaType.dartObject;
    }

    return new java.ClassDecl(type,
        access: java.Access.Public, 
        fields: fields, 
        methods: methods, 
        constructors: constructorDelegators,
        supertype: supertype,
        isAbstract: node.isAbstract);
  }

  java.FieldDecl buildClassField(dart.Field node) {
    // Non-static fields are initialized in the constructor
    java.Expression initializer = node.isStatic
      ? buildCastedExpression(node.initializer, node.type)
      : new java.NullLiteral();

    return new java.FieldDecl(node.name.name, node.type.accept(this),
        initializer: initializer,
        access: java.Access.Public,
        isStatic: node.isStatic,
        isFinal: node.isFinal);
  }

  @override
  java.FieldDecl visitField(dart.Field node) {
    return new java.FieldDecl(node.name.name, node.type.accept(this),
        initializer: buildCastedExpression(node.initializer, node.type),
        access: java.Access.Public,
        isStatic: node.isStatic,
        isFinal: node.isFinal);
  }

  java.MethodDef buildGetter(dart.Field node) {
    String methodName = javaMethodName(
      node.name.name, dart.ProcedureKind.Getter);
    var body = wrapInJavaBlock(new java.ReturnStmt(
      new java.FieldAccess(buildDefaultReceiver(node.isStatic), 
        new java.IdentifierExpr(node.name.name))));

    return new java.MethodDef(methodName, body, [], 
      returnType: node.type.accept(this),
      isStatic: node.isStatic);
  }

  java.MethodDef buildSetter(dart.Field node) {
    String methodName = javaMethodName(
      node.name.name, dart.ProcedureKind.Setter);
    var fieldAssignment = new java.AssignmentExpr(
      new java.FieldAccess(buildDefaultReceiver(node.isStatic), 
        new java.IdentifierExpr(node.name.name)), 
      new java.IdentifierExpr("value"));
    var returnStmt = new java.ReturnStmt(new java.IdentifierExpr("value"));
    var body = new java.Block([
      new java.ExpressionStmt(fieldAssignment), 
      returnStmt]);
    var param = new java.VariableDecl("value", node.type.accept(this));

    return new java.MethodDef(methodName, body, [param], 
      returnType: node.type.accept(this),
      isStatic: node.isStatic);
  }

  @override
  java.Statement visitFieldInitializer(dart.FieldInitializer node) {
    var fieldAssignment = new java.AssignmentExpr(
      new java.FieldAccess(buildDefaultReceiver(false), 
        new java.IdentifierExpr(node.field.name.name)), 
      buildCastedExpression(node.value, node.field.type));

    return new java.ExpressionStmt(fieldAssignment);
  }

  /// Translates arguments for method calls and constructor invocations.
  /// 
  /// Handles positional arguments, type arguments, and optional arguments,
  /// but not named arguments at the moment.
  /// 
  /// This method takes a function node as a parameter determine if a
  /// type cast must be inserted before passing an argument.
  List<java.Expression> buildArguments(dart.Arguments node, 
    dart.FunctionNode target) {
    // TODO(springerm): Handle parameters other than positional
    var result = new List<java.Expression>();

    Iterable<java.JavaType> typeArguments = node.types.map((t) 
      => t.accept(this)) as Iterable<JavaType>;
    // Calling convention: Type arguments as first arguments 
    // for static invocations, then positional arguments
    // TODO(springerm, andrewkrieger): Use proper types once implemented
    result.addAll(typeArguments.map((t) => new java.TypeExpr(t)));

    for (int i = 0; i < node.positional.length; i++) {
      result.add(buildCastedExpression(
        node.positional[i],
        target.positionalParameters[i].type));
    }

    return result;
  }

  @override
  java.Statement visitSuperInitializer(dart.SuperInitializer node) {
    return new java.ExpressionStmt(new java.SuperMethodInvocation(
      Constants.constructorMethodPrefix,
      buildArguments(node.arguments, node.target.function)));
  }

  String capitalizeString(String str) =>
      str[0].toUpperCase() + str.substring(1);

  String javaMethodName(String methodName, dart.ProcedureKind kind) {
    switch (kind) {
      case dart.ProcedureKind.Method:
        return methodName;
      case dart.ProcedureKind.Operator:
        var translatedMethodName = Constants.operatorToMethodName[methodName];
        if (translatedMethodName == null) {
          throw new CompileErrorException(
              "${methodName} is not an operator.");
        }
        return translatedMethodName;
      case dart.ProcedureKind.Getter:
        return "get" + capitalizeString(methodName);
      case dart.ProcedureKind.Setter:
        return "set" + capitalizeString(methodName);
      default:
        // TODO(springerm): handle remaining kinds
        throw new CompileErrorException(
            "Method kind ${kind} not implemented yet.");
    }
  }

  Iterable<java.Statement> buildTempVarDecls() {
    return tempVars.values.map((v) =>
      new java.VariableDeclStmt(
          new java.VariableDecl(v.name, v.type.accept(this))));
  }

  @override
  java.MethodDef visitProcedure(dart.Procedure procedure) {
    String methodName = javaMethodName(procedure.name.name, procedure.kind);
    java.JavaType returnType = procedure.function.returnType.accept(this);
    // TODO(springerm): handle named parameters, etc.
    List<java.VariableDecl> parameters = procedure.function.positionalParameters
        .map(visitVariableDeclaration)
        .toList();
    var isStatic = procedure.isStatic;

    java.Statement body;
    if (procedure.isExternal) {
      // Generate a method call to a static Java method.
      // Every external Dart method must be annotated with "JavaCall".
      // TODO(stanm): add check.
      String externalJavaMethod =
          getSimpleAnnotation(procedure, Constants.javaCallAnnotation);
      List<String> methodTokens = externalJavaMethod.split(".");
      var extReceiver = new java.ClassRefExpr(
          new java.ClassOrInterfaceType.parseTopLevel(
              methodTokens.getRange(0, methodTokens.length - 1).join(".")));
      var extMethodName = methodTokens.last;

      List<java.Expression> arguments = [];
      if (!isStatic) {
        // First argument is "this"
        arguments
            .add(new java.IdentifierExpr(Constants.javaStaticThisIdentifier));
      }
      // Remaining arguments are parameters of Dart method
      arguments.addAll(parameters.map((p) => new java.IdentifierExpr(p.name)));

      if (procedure.function.returnType is dart.VoidType) {
        body = new java.ExpressionStmt(
            new java.MethodInvocation(extReceiver, extMethodName, arguments));
      } else {
        body = new java.ReturnStmt(
            new java.MethodInvocation(extReceiver, extMethodName, arguments));
      }
    } else {
      // Normal Dart method
      if (!procedure.isAbstract) {
        assert(tempVars == null);
        tempVars = new Map<dart.VariableDeclaration, TemporaryVariable>();

        body = wrapInJavaBlock(buildStatement(procedure.function.body));

        // Insert declarations of temporary variables
        (body as java.Block).statements.insertAll(0, buildTempVarDecls());
        tempVars = null;
      }
    }

    if (methodName == "main" && procedure.enclosingClass == null) {
      if (parameters.length > 1) {
        throw new CompileErrorException(
            'Not implemented yet: Cannot handle main functions with more than'
            ' one argument.');
      }
      if (parameters.length == 1 &&
          parameters[0].type != java.JavaType.object) {
        throw new CompileErrorException(
            'Not implemented yet: Cannot handle main functions with an argument'
            ' that is not of dynamic type.');
      }

      var stringArrayType = new java.ArrayType(java.JavaType.string, 1);
      if (parameters.length == 0) {
        parameters.add(new java.VariableDecl("args", stringArrayType));
      } else {
        parameters[0].type = stringArrayType;
      }

      // Ignore the declared/dynamic return type of main and set it to void.
      // TODO(stanm): make sure there are no odd return statements in body, e.g.
      // `return 1337;`: return values from main are ignored in Dart, as it is
      // assumed that main has a `void` type.
      returnType = java.JavaType.void_;
    }

    if (!procedure.isAbstract) {
      // Make sure body is a [java.Block]
      body = wrapInJavaBlock(body);
    }

    return new java.MethodDef(methodName, body, parameters, 
      returnType: returnType, isStatic: isStatic, isFinal: false,
      isAbstract: procedure.isAbstract);
  }

  /// Builds an empty constructor invoking the super empty constructor.
  ///
  /// An empty constructor contains an empty body and calls the empty
  /// super constructor. It is necessary to prevent Java from calling the
  /// default super constructor. The parameter is merely used as a marker
  /// to dispatch to the correct (overloaded) constructor.
  java.Constructor buildEmptyConstructor(java.ClassOrInterfaceType classType) {
    java.Statement superCall = 
      new java.SuperConstructorInvocation(<java.Expression>[
        new java.IdentifierExpr("arg")]);

    return new java.Constructor(
      classType,
      wrapInJavaBlock(superCall),
      <java.VariableDecl>[
        new java.VariableDecl("arg", java.JavaType.emptyConstructorMarker)]);
  }

  /// Translates a Kernel AST constructor to a Java constructor and method.
  /// 
  /// Creates a Java constructor consisting of a delegator (actual Java
  /// constructor that delegates to an instance method) and a body method
  /// (Java instance method). The constructor performs the following steps:
  /// 
  /// 1. Direct field initializations (at VariableDecl site)
  /// 2. Field initializer list
  /// 3. Super constructor
  /// 4. Constructor body
  /// 
  /// It is hard to implement these semantics with a plain Java constructor
  /// because the super constructor invocation must always be the first
  /// statement in a Java constructor. Therefore, we put the body of the
  /// constructor in an instance method.
  /// 
  /// A Java super constructor should only be invoked if that is explicitly
  /// specified in the code. We do not want Java to automatically call the 
  /// super constructor (since Dart and Java have different semantics regarding
  /// the execution order). For that reason, every class has an "empty"
  /// constructor, which is invoked at the beginning of the delegator. That
  /// constructor does nothing except for invoking the empty constructor of
  /// its superclass.
  /// 
  /// Note, that we could have used a static method as an entry point for
  /// instance creation (instead of the Java constructor), avoiding the empty
  /// constructor, but that would mess up interoperability.
  _JavaConstructor buildConstructor(dart.Constructor node,
    List<dart.Field> fields) {
    Iterable<dart.Initializer> fieldInitializers = 
      node.initializers.where((i) => i.runtimeType == dart.FieldInitializer);
    Iterable<java.Statement> javaFieldInitializers = 
      fieldInitializers.map((i) => i.accept(this));

    // Field initializers that are part of VariableDecls
    Iterable<java.Statement> javaDirectFieldInitializers =
      fields.where((f) => f.initializer != null)
        .map((f) => new java.ExpressionStmt(new java.AssignmentExpr(
          new java.FieldAccess(buildDefaultReceiver(false),
            new java.IdentifierExpr(f.name.name)),
          buildCastedExpression(f.initializer, f.type))));

    // There is either 0 or 1 super initializers
    Iterable<dart.Initializer> superInitializers = 
      node.initializers.where((i) => i.runtimeType == dart.SuperInitializer);
    Iterable<java.Statement> javaSuperInitializers = 
      superInitializers.map((i) => i.accept(this));

    java.Block body;
    if (node.function.body == null) {
      // Constructor may not have a body (sometimes also contains a body
      // with an [EmptyStatement]).
      body = new java.Block(<java.Statement>[]);
    } else {
      body = wrapInJavaBlock(buildStatement(node.function.body));
    }
    body.statements.insertAll(0, javaSuperInitializers);
    body.statements.insertAll(0, javaFieldInitializers);
    body.statements.insertAll(0, javaDirectFieldInitializers);

    // TODO(springerm): handle named parameters, etc.
    List<java.VariableDecl> parameters = node.function.positionalParameters
        .map(visitVariableDeclaration)
        .toList();

    var constructorCall = new java.MethodInvocation(
      buildDefaultReceiver(false),
      Constants.constructorMethodPrefix,
      parameters.map((p) => new java.IdentifierExpr(p.name)).toList());

    var delegatorBlock = new java.Block(<java.Statement>[
      new java.SuperConstructorInvocation([new java.CastExpr(
        new java.NullLiteral(), java.JavaType.emptyConstructorMarker)]),
      new java.ExpressionStmt(constructorCall)]);

    java.Constructor delegator = new java.Constructor(
      getJavaType(thisDartClass), 
      delegatorBlock,
      parameters);

    java.MethodDef constructorBody = new java.MethodDef(
      Constants.constructorMethodPrefix,
      body,
      parameters,
      access: java.Access.Protected);

    return new _JavaConstructor(delegator, constructorBody);
  }

  /// Wraps a Java statement in a block, if [stmt] is not already a block.
  java.Block wrapInJavaBlock(java.Statement stmt) {
    if (stmt is java.Block) {
      return stmt;
    } else {
      return new java.Block([stmt]);
    }
  }

  @override
  java.Block visitBlock(dart.Block node) {
    return new java.Block(node.statements.map(buildStatement).toList());
  }

  @override
  java.Block visitEmptyStatement(dart.EmptyStatement node) {
    // TODO(springerm): We don't have an empty statement right now,
    // but an empty block has no effect
    return new java.Block(<java.Statement>[]);
  }

  @override
  java.IfStmt visitIfStatement(dart.IfStatement node) {
    return new java.IfStmt(
        node.condition.accept(this),
        wrapInJavaBlock(buildStatement(node.then)),
        node.otherwise == null
            ? null
            : wrapInJavaBlock(buildStatement(node.otherwise)));
  }

  @override
  java.ConditionalExpr visitConditionalExpression(
    dart.ConditionalExpression node) {
    return new java.ConditionalExpr(
      node.condition.accept(this),
      node.then.accept(this),
      node.otherwise.accept(this));
  }

  @override
  java.WhileStmt visitWhileStatement(dart.WhileStatement node) {
    return new java.WhileStmt(
      node.condition.accept(this),
      wrapInJavaBlock(buildStatement(node.body)));
  } 

  @override
  java.DoStmt visitDoStatement(dart.DoStatement node) {
    return new java.DoStmt(
      node.condition.accept(this),
      wrapInJavaBlock(buildStatement(node.body)));
  }

  @override
  java.ForStmt visitForStatement(dart.ForStatement node) {
    return new java.ForStmt(
      node.variables.map((v) => v.accept(this)).toList() 
        as List<java.VariableDecl>,
      node.condition.accept(this),
      node.updates.map((u) => u.accept(this)).toList()
        as List<java.Expression>,
      wrapInJavaBlock(buildStatement(node.body)));
  }

  @override
  java.ReturnStmt visitReturnStatement(dart.ReturnStatement node) {
    // Find procedure
    dart.TreeNode procNode = node;
    while (procNode is! dart.Procedure) {
      procNode = procNode.parent;
    }

    return new java.ReturnStmt(
      buildCastedExpression(
        node.expression,
        (procNode as dart.Procedure).function.returnType));
  }

  @override
  java.ExpressionStmt visitExpressionStatement(dart.ExpressionStatement node) {
    return new java.ExpressionStmt(node.expression.accept(this));
  }

  /// Builds a method invocation where the call target is not statically known.
  java.MethodInvocation buildDynamicMethodInvocation(dart.Expression receiver, 
      String methodName, List<java.Expression> arguments) {
    // Translate receiver
    java.Expression recv = receiver.accept(this);
    dart.DartType recvType = receiver.staticType;

    if (recvType is! dart.InterfaceType) {
      throw new CompileErrorException(
        "Can only handle method invocation where receiver is an InterfaceType "
        "(found ${recvType.runtimeType})");
    }

    dart.Class classNode = (recvType as dart.InterfaceType).classNode;

    // Change method name if annotated with @JavaMethod
    if (compilerState.hasJavaImpl(classNode)) {
      methodName = compilerState.getJavaMethodName(classNode, methodName);
    }

    // Intercept method call if necessary
    if (compilerState.usesHelperFunction(classNode, methodName)) {
      java.ClassOrInterfaceType helperClass =
          compilerState.getHelperClass(classNode);

      // Generate static call to helper function.
      java.ClassRefExpr helperRefExpr = new java.ClassRefExpr(helperClass);
        // Dynamic method invocation
      return new java.MethodInvocation(
        helperRefExpr, methodName, [recv]..addAll(arguments));
    }

    return new java.MethodInvocation(recv, methodName, arguments);
  }

  @override
  java.MethodInvocation visitPropertyGet(dart.PropertyGet node) {
    String methodName =
        javaMethodName(node.name.name, dart.ProcedureKind.Getter);
    return buildDynamicMethodInvocation(node.receiver, methodName, []);
  }

  /// Finds a [dart.Procedure] in a class and its superclasses.
  dart.Procedure findProcedureInClassHierarchy(
    // TODO(springerm): Check mixins
    String name, dart.Class class_) {
    dart.Class nextClass = class_;
    do {
      Iterable<dart.Procedure> matches = nextClass.procedures.where((p) =>
        p.name.name == name);
      if (matches.isNotEmpty) {
        return matches.single;
      }
      nextClass = nextClass.superclass;
    } while (nextClass != null);
    return null;
  }

  /// Find a [dart.Field] in a class and its superclasses.
  dart.Field findFieldInClassHierarchy(
    // TODO(springerm): Check mixins
    String name, dart.Class class_) {
    dart.Class nextClass = class_;
    do {
      Iterable<dart.Field> matches = nextClass.fields.where((p) =>
        p.name.name == name);
      if (matches.isNotEmpty) {
        return matches.single;
      }
      nextClass = nextClass.superclass;
    } while (nextClass != null);
    return null;
  }

  @override
  java.MethodInvocation visitPropertySet(dart.PropertySet node) {
    String methodName =
        javaMethodName(node.name.name, dart.ProcedureKind.Setter);

    if (node.receiver.staticType is! dart.InterfaceType) {
      throw new CompileErrorException(
        "Can only handle property set where receiver is an InterfaceType "
        "(found ${node.staticType.runtimeType})");
    }

    dart.DartType expectedType;
    dart.Class classNode = (node.receiver.staticType as dart.InterfaceType)
      .classNode;

    dart.Procedure procedure = findProcedureInClassHierarchy(
      node.name.name, classNode);
    dart.Field field = findFieldInClassHierarchy(
      node.name.name, classNode);

    if (procedure != null && procedure.kind == dart.ProcedureKind.Setter) {
      expectedType = procedure.function.positionalParameters.first.type;
    } else if (field != null) {
      expectedType = field.type;
    } else {
      throw new CompileErrorException(
        "Field or setter not found in receiver class."); 
    }

    return buildDynamicMethodInvocation(node.receiver, methodName, 
        [buildCastedExpression(node.value, expectedType)]);
  }

  @override
  java.MethodInvocation visitMethodInvocation(dart.MethodInvocation node) {
    String name = node.name.name;
    // Expand operator symbol to Java-compatible method name
    name = Constants.operatorToMethodName[name] ?? name;

    if (Constants.objectMethods.contains(name)) {
      // This method is defined on Object and must dispatch to ObjectHelper
      // directly to handle "null" values correctly
      java.ClassOrInterfaceType helperClass =
          compilerState.getHelperClass(compilerState.objectClass);
      // Generate static call to helper function.
      java.ClassRefExpr helperRefExpr = new java.ClassRefExpr(helperClass);
      List<java.Expression> javaArgs = [node.receiver.accept(this)]..addAll(
        node.arguments.positional.map((i) => i.accept(this)));

      return new java.MethodInvocation(
        helperRefExpr, name, javaArgs);
    } 

    if (node.receiver.staticType is! dart.InterfaceType) {
      throw new CompileErrorException(
        "Can only handle property set where receiver is an InterfaceType "
        "(found ${node.staticType.runtimeType})");
    }

    dart.FunctionNode targetFunction;
    var interfaceType = node.receiver.staticType as dart.InterfaceType;
    dart.Class classNode = interfaceType.classNode;

    dart.Procedure procedure = findProcedureInClassHierarchy(
      node.name.name, classNode);

    if (procedure != null) {
      targetFunction = procedure.function;
    } else {
      throw new CompileErrorException(
        "Method ${node.name.name} not found in receiver class ${classNode}."); 
    }

    // Call specialized generic method is available
    Iterable<java.JavaType> javaTypeArguments = 
      interfaceType.typeArguments.map((t) => t.accept(this));
    if (java.JavaType.hasGenericSpecialization(javaTypeArguments)) {
      name = name + Constants.primitiveSpecializationSuffix;
    }

    return buildDynamicMethodInvocation(
        node.receiver, name, buildArguments(node.arguments, targetFunction));
  }

  @override
  java.SuperMethodInvocation visitSuperMethodInvocation(
    dart.SuperMethodInvocation node) {
    return new java.SuperMethodInvocation(
      node.name.name,
      buildArguments(node.arguments, node.target.function));
  }

  @override
  java.MethodInvocation visitStaticInvocation(dart.StaticInvocation node) {
    java.Expression receiver;
    dart.Class receiverClass = null;
    String methodName = node.target.name.name;

    if (node.target.enclosingClass == null) {
      receiver = new java.ClassRefExpr(
        compilerState.getTopLevelClass(node.target.enclosingLibrary));
    } else {
      receiver = new java.ClassRefExpr(
        compilerState.getClass(node.target.enclosingClass));
      receiverClass = node.target.enclosingClass;
    }

    // Change method name if annotated with @JavaMethod
    if (compilerState.hasJavaImpl(receiverClass)) {
      methodName = compilerState.getJavaMethodName(receiverClass, methodName);
    }

    List<java.Expression> args = buildArguments(
      node.arguments, node.target.function);
    Iterable<java.JavaType> typeArguments = node.arguments.types.map((t) 
      => t.accept(this)) as Iterable<JavaType>;

    // Intercept method call if necessary
    if (compilerState.usesHelperFunction(receiverClass, methodName)) {
      java.ClassOrInterfaceType helperClass =
          compilerState.getHelperClass(receiverClass);

      // Generate static call to helper function.
      java.ClassRefExpr helperRefExpr = new java.ClassRefExpr(helperClass);
      // Static method invocation
      java.FieldAccess staticNested = new java.FieldAccess(
        helperRefExpr, 
        new java.IdentifierExpr(Constants.helperNestedClassForStatic));
      return new java.MethodInvocation(staticNested, methodName, args);
    }

    if (typeArguments.isNotEmpty) {
      // This is a call to a generic class, make sure to choose the correct
      // specialization
      receiver = new java.FieldAccess(receiver, new java.IdentifierExpr(
        java.JavaType.getGenericImplementation(typeArguments)));
    }

    return new java.MethodInvocation(receiver, methodName, args);
  }

  @override
  java.NewExpr visitConstructorInvocation(dart.ConstructorInvocation node) {
    // TODO(springerm): Check for usesHelperFunction
    // TODO(springerm): Handle other parameter types
    List<java.Expression> args = buildArguments(
      node.arguments, node.target.function);

    java.ClassOrInterfaceType type = 
      node.target.enclosingClass.thisType.accept(this);

    if (type == java.JavaType.object) {
      // Make sure that "new Object" results in "new DartObject"
      // TODO(springerm): Remove hard-coded special case once we 
      // figure out interop
      type = java.JavaType.dartObject;
    }

    return new java.NewExpr(new java.ClassRefExpr(type), args);
  }

  /// Returns the enclosing class type of a member or the top level class type
  /// if there is no enclosing class.
  java.ClassOrInterfaceType getEnclosingOfMember(dart.Member member) {
    if (member.enclosingClass == null) {
      // Belongs to top top level
      return compilerState.getTopLevelClass(member.enclosingLibrary);
    } else {
      return member.enclosingClass.thisType.accept(this);
    }
  }

  @override
  java.FieldAccess visitStaticGet(dart.StaticGet node) {
    assert(!node.target.isInstanceMember);

    if (node.target is dart.Field) {
      // Static field read
      dart.Field field = node.target;

      // TODO(springerm): Reconsider passing method name here (it is a field!)
      if (compilerState.usesHelperFunction(
        node.target.enclosingClass, field.name.name)) {
        // Access static field in helper class
        java.ClassOrInterfaceType helperClass =
            compilerState.getHelperClass(node.target.enclosingClass);
        java.ClassRefExpr helperRefExpr = new java.ClassRefExpr(helperClass);
        java.FieldAccess staticNested = new java.FieldAccess(
          helperRefExpr, 
          new java.IdentifierExpr(Constants.helperNestedClassForStatic));
        return new java.FieldAccess(
          staticNested, new java.IdentifierExpr(field.name.name));
      } else {
        // Regular static field access
        java.Expression fieldAccess = new java.FieldAccess(
          new java.ClassRefExpr(getEnclosingOfMember(node.target)), 
          new java.IdentifierExpr(field.name.name));
        return fieldAccess;
      }
    } else {
      throw new CompileErrorException(
          'Not implemented yet: Cannot handle StaticGet for '
          '${node.target.runtimeType}');
    }
  }

  @override
  java.AssignmentExpr visitStaticSet(dart.StaticSet node) {
    assert(!node.target.isInstanceMember);

    if (node.target is dart.Field) {
      // Static field read
      dart.Field field = node.target;

      // TODO(springerm): Reconsider passing method name here (it is a field!)
      if (compilerState.usesHelperFunction(
        node.target.enclosingClass, field.name.name)) {
        throw new CompileErrorException(
            'Not implemented yet: Cannot handle StaticSet for '
            'types with helper classes');
      } else {
        // Regular static field access
        java.Expression fieldAccess = new java.FieldAccess(
          new java.ClassRefExpr(getEnclosingOfMember(node.target)), 
          new java.IdentifierExpr(field.name.name));

        java.Expression newValue;
        if (node.target is dart.Field) {
          newValue = buildCastedExpression(node.value, 
            (node.target as dart.Field).type);
        } else if (node.target is dart.Procedure) {
          // Calling a setter
          newValue = buildCastedExpression(node.value, 
            (node.target as dart.Procedure)
              .function.positionalParameters.first.type);
        }

        return new java.AssignmentExpr(fieldAccess, newValue);
      }
    } else {
      throw new CompileErrorException(
          'Not implemented yet: Cannot handle StaticSet for '
          '${node.target.runtimeType}');
    }
  }

  @override
  java.UnaryExpr visitNot(dart.Not node) {
    return new java.UnaryExpr(node.operand.accept(this), "!");
  }

  @override
  java.Expression visitStringConcatenation(dart.StringConcatenation node) {
    Iterable<java.Expression> strings = node.expressions.map((e) =>
      new java.MethodInvocation(e.accept(this),
        Constants.toStringMethodName));

    return strings.reduce((value, element) =>
      new java.BinaryExpr(value, element, "+"));
  }

  @override
  java.NullLiteral visitNullLiteral(dart.NullLiteral node) {
    return new java.NullLiteral();
  }


  @override
  java.BinaryExpr visitLogicalExpression(dart.LogicalExpression node) {
    return new java.BinaryExpr(
      node.left.accept(this),
      node.right.accept(this),
      node.operator);
  }

  /// Assuming that [node] has a single annotation of type [annotation] and
  /// that annotation has a single String parameter, return the parameter
  /// value. If the assumptions do not apply, throw an exception.
  String getSimpleAnnotation(dart.Procedure node, String annotation,
      [String fieldName = "name"]) {
    // TODO(springerm): Try to use DartTypes here instead of Strings
    var obj = node.analyzerMetadata
        .firstWhere((i) => i.type.toString() == annotation);
    if (obj == null) {
      throw new CompileErrorException(
          "Unable to find ${annotation} annotation");
    }

    return obj.getField(fieldName).toStringValue();
  }

  /// Converts a Dart class name to a Java class name.
  java.ClassOrInterfaceType getJavaType(dart.Class dartClass) {
    return compilerState.getClass(dartClass);
  }

  /// Build a reference to a Dart class.
  java.ClassRefExpr buildClassReference(dart.Class dartClass) {
    return new java.ClassRefExpr(getJavaType(dartClass));
  }

  java.ClassRefExpr buildThisClassRefExpr() {
    return buildClassReference(thisDartClass);
  }

  /// Build a reference to "this".
  java.Expression buildDefaultReceiver(bool isStatic) {
    if (isStatic) {
      return buildThisClassRefExpr();
    } else {
      assert(!compilerState.isJavaClass(thisDartClass));
      return new java.IdentifierExpr("this");
    }
  }

  /// Returns the [dart.DartType] for the current class.
  dart.InterfaceType getThisClassDartType() {
    return thisDartClass.thisType;
  }

  @override
  java.IdentifierExpr visitThisExpression(dart.ThisExpression node) {
    return buildDefaultReceiver(false);
  }

  @override
  java.IdentifierExpr visitVariableGet(dart.VariableGet node) {
    if (node.variable.name == null) {
      // This must be a temporary variable
      String name = tempVars[node.variable]?.name;

      if (name == null) {
        throw new CompileErrorException("Expected temporary variable.");
      }

      return new java.IdentifierExpr(name);
    } else {
      return new java.IdentifierExpr(node.variable.name);
    }
  }

  @override
  java.AssignmentExpr visitVariableSet(dart.VariableSet node) {
    return new java.AssignmentExpr(
        new java.IdentifierExpr(node.variable.name), 
        buildCastedExpression(node.value, node.variable.type));
  }

  /// Translates a node and inserts a cast depending on the expected type.
  /// 
  /// This method is currently used only for supporting covariant generics.
  /// This will likely change in the future; plans are to remove Java generics
  /// and to use Java Object. Casts will then have to be inserted at a
  /// different point.
  /// 
  /// Java generics are not covariant but Dart generics are. The current 
  /// implementation uses both Java generics and an additional field for 
  /// reified generics in generated Java code. Using Java generics has the
  /// benefit that less explicit casts are necessary, which makes codegen
  /// easier (see DartList.java for an example). For example:
  /// 
  /// List<int> list = ...
  /// int a = list[1]
  /// 
  /// This code snippet does not require a Java cast because it is translated
  /// to the following:
  /// 
  /// DartList<Integer> list = ...
  /// Integer a = list.operatorAt(1) --> returns Integer
  /// 
  /// If List were not generic, the return type would be an Object and the code
  /// generator would have to insert an explicit cast. The following generated
  /// Java code is troublesome:
  /// 
  /// DartList<String> stringList = ...
  /// DartList<Object> list = stringList;
  /// 
  /// In order to make that code compile, this method inserts an additional
  /// cast that does *not* result in a runtime check.
  /// 
  /// DartList<Object> list = (DartList) stringList;
  /// 
  /// Note, that Dart checks types at a different point of time as Java (i.e.,
  /// when adding something to a list etc.), but that is another issue. Afaik,
  /// it is not possible to get rid of the runtime type check when accessing
  /// an element in the list in Java without writing bytecode directly. Even
  /// then, the bytecode verifier might reject the code.
  /// 
  /// No cast is inserted if both object and expected type are specializations,
  /// e.g., assigning a List<int> to a List<int>-typed variable
  java.Expression buildCastedExpression(dart.Expression node, 
    dart.DartType expectedType) {
    if (node == null) {
      // This method is sometimes called on optional nodes, e.g. initializers
      return null;
    }

    dart.DartType type = node.staticType;
    java.ClassOrInterfaceType targetType;

    if (type is dart.InterfaceType && expectedType is dart.InterfaceType) {
      Iterable<java.JavaType> javaTypeArguments = 
        type.typeArguments.map((t) => t.accept(this));
      Iterable<java.JavaType> expectedJavaTypeArguments = 
        expectedType.typeArguments.map((t) => t.accept(this));

      if (javaTypeArguments.isNotEmpty 
        && !(
          java.JavaType.hasGenericSpecialization(javaTypeArguments) &&
          java.JavaType.hasGenericSpecialization(expectedJavaTypeArguments))) {
        // Insert a cast
        targetType = expectedType.accept(this);
        targetType.typeArguments.clear();

        return new java.CastExpr(node.accept(this), targetType);
      }
    }

    return node.accept(this);
  }

  @override
  java.Expression visitLet(dart.Let node) {
    // TODO(springerm): Need to seriously optimize this for simple
    // incremenets/decrements

    // Let expressions require two operations: (1) create and assign a 
    // temporary variable and (2) evaluate and return an expression.
    // This is hard to do in an expression because (1) is a statement.
    // Here's a way to do it:
    // Create a temporary variable at the beginning of the method and 
    // assign it Let.variable where the let expression occurs. Pass this
    // assignment expression as an argument to the `comma` method (sequence
    // point method) along with the body of the let expression. That is a way
    // to implement Let expressions without lambdas. `comma` simply returns
    // the second parameter and acts as a sequence point (comma in C/C++).

    String tempIdentifier = nextTempVarIdentifier();
    tempVars[node.variable] = new TemporaryVariable(
      tempIdentifier,
      node.variable.type);

    var assignment = new java.AssignmentExpr(
      new java.IdentifierExpr(tempIdentifier),
      buildCastedExpression(node.variable.initializer, node.variable.type));

    return new java.MethodInvocation(
      new java.ClassRefExpr(java.JavaType.letHelper),
      Constants.sequencePointMethodName,
      <java.Expression>[
        assignment,
        node.body.accept(this)]);
  }

  @override
  java.Expression visitListLiteral(dart.ListLiteral node) {
    var args = <java.Expression>[];

    List<java.JavaType> typeArguments = 
      <JavaType>[node.typeArgument.accept(this)];
    // Calling convention: Type arguments as first arguments 
    // for static invocations, then positional arguments
    // TODO(springerm, andrewkrieger): Use proper types once implemented
    args.addAll(typeArguments.map((t) => new java.TypeExpr(t)));
    args.addAll(node.expressions.map((e) =>
      buildCastedExpression(e, node.typeArgument)));

    java.Expression listClass = new java.ClassRefExpr(
      compilerState.getClass(compilerState.listClass));

    if (typeArguments.isNotEmpty) {
      // This is a call to a generic class, make sure to choose the correct
      // specialization
      listClass = new java.FieldAccess(listClass, new java.IdentifierExpr(
        java.JavaType.getGenericImplementation(typeArguments)));
    }

    return new java.MethodInvocation(
      listClass, 
      Constants.listInitializerMethodName,
      args);
  }

  @override
  java.BoolLiteral visitBoolLiteral(dart.BoolLiteral node) {
    return new java.BoolLiteral(node.value);
  }

  @override
  java.IntLiteral visitIntLiteral(dart.IntLiteral node) {
    return new java.IntLiteral(node.value);
  }

  @override
  java.DoubleLiteral visitDoubleLiteral(dart.DoubleLiteral node) {
    return new java.DoubleLiteral(node.value);
  }

  @override
  java.StringLiteral visitStringLiteral(dart.StringLiteral node) {
    return new java.StringLiteral(node.value);
  }

  /// Convert a Dart statement to a Java statement.
  ///
  /// Some statements require special handling.
  java.Statement buildStatement(dart.Statement node) {
    var result = node.accept(this);

    if (node is dart.VariableDeclaration) {
      // A variable declaration should sometimes be a statement. In that case,
      // we ensure that the variable is initialized (to null if necessary).
      var decl = result as java.VariableDecl;
      decl.initializer ??= new java.NullLiteral();
      return new java.VariableDeclStmt(decl);
    } else {
      return result;
    }
  }

  /// This is the default visitor method for DartType.
  @override
  java.JavaType defaultDartType(dart.DartType node) {
    throw new CompileErrorException("Unimplemented type: ${node.runtimeType}");
  }

  @override
  java.ReferenceType visitDynamicType(dart.DynamicType node) {
    // TODO(stanm): #implementDynamic: Object is not the best representation
    // of dynamic: implement better.
    return java.JavaType.object;
  }

  @override
  java.VoidType visitVoidType(dart.VoidType node) {
    return java.JavaType.void_;
  }

  @override
  java.ClassOrInterfaceType visitInterfaceType(dart.InterfaceType node) {
    java.ClassOrInterfaceType type = compilerState.getClass(node.classNode);

    if (node.typeArguments != null && node.typeArguments.isNotEmpty) {
      return type.withTypeArguments(
        node.typeArguments.map((t) => t.accept(this)).toList());
    } else {
      return type;
    }
  }

  @override
  java.VariableDecl visitVariableDeclaration(dart.VariableDeclaration node) {
    return new java.VariableDecl(node.name, node.type.accept(this),
        isFinal: node.isFinal, 
        initializer: buildCastedExpression(node.initializer, node.type));
  }
}
