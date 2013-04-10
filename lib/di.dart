import 'mirrors.dart';
import 'dart:async';
import 'dart:collection';

class NoProviderException implements Exception {
  final String message;

  const NoProviderException(this.message);
  const NoProviderException.forType(String typeName) : this('No provider for ${typeName}!');
}

class CircularDependencyException implements Exception {
  final String message;

  const CircularDependencyException(this.message);
}


abstract class Provider {
  dynamic get(getInstanceByTypeName);
}


class _ValueProvider implements Provider {
  dynamic value;

  _ValueProvider(value) {
    this.value = value;
  }

  dynamic get(getInstanceByTypeName) {
    return reflect(value);
  }
}


class _TypeProvider implements Provider {
  Type type;

  _TypeProvider(Type type) {
    this.type = type;
  }

  dynamic get(getInstanceByTypeName) {
    ClassMirror cm = _getClassMirrorByTypeName(type.toString());
    MethodMirror ctor = cm.constructors.values.first;

    resolveArgument(p) {
      return getInstanceByTypeName(p.type.simpleName);
    }

    var positionalArgs = ctor.parameters.map(resolveArgument).toList();
    var namedArgs = null;

    return deprecatedFutureValue(cm.newInstance(ctor.constructorName, positionalArgs, namedArgs));
  }
}


class Module extends HashMap<String, Provider> {

  void value(Type id, value) {
    this[id.toString()] = new _ValueProvider(value);
  }

  void type(Type id, Type type) {
    this[id.toString()] = new _TypeProvider(type);
  }
}


// terrible hack because we can't get a qualified name from a Type
// dartbug.com/8041
// dartbug.com/9395
ClassMirror _getClassMirrorByTypeName (String typeName) {
  for (var lib in currentMirrorSystem().libraries.values) {
    if (lib.classes.containsKey(typeName)) {
      return lib.classes[typeName];
    }
  }
}


class Injector {
  final List<String> PRIMITIVE_TYPES = <String>['dynamic', 'num', 'String', 'bool'];

  // should be <Type, Provider>
  Map<String, Provider> providers = new Map<String, Provider>();
  // should be <Type, dynamic>
  Map<String, dynamic> instances = new Map<String, dynamic>();

  List<String> resolving = new List<String>();
  
  Injector([List<Module> modules]) {
    if (?modules) {
      modules.forEach((module) {
        providers.addAll(module);
      });
    }
  }

  dynamic _getInstanceByTypeName(String typeName) {
    if (PRIMITIVE_TYPES.contains(typeName)) {
      String graph = resolving.join(' -> ') + ' -> ' + typeName;
      resolving.clear();
      throw new NoProviderException('Cannot inject a primitive type of ${typeName}! (resolving ${graph})');
    }

    if (instances.containsKey(typeName)) {
      return instances[typeName];
    }

    if (resolving.contains(typeName)) {
      String graph = resolving.join(' -> ') + ' -> ' + typeName;
      resolving.clear();
      throw new CircularDependencyException('Cannot resolve a circular dependency! (resolving ${graph})');
    }

    resolving.add(typeName);

    if (providers.containsKey(typeName)) {
      instances[typeName] = providers[typeName].get(_getInstanceByTypeName);
    } else {
      // implicit type provider
      ClassMirror cm = _getClassMirrorByTypeName(typeName);
      MethodMirror ctor = cm.constructors.values.first;

      resolveArgument(p) {
        return _getInstanceByTypeName(p.type.simpleName);
      }

      var positionalArgs = ctor.parameters.map(resolveArgument).toList();
      var namedArgs = null;

      instances[typeName] = deprecatedFutureValue(cm.newInstance(ctor.constructorName, positionalArgs, namedArgs));
    }

    resolving.removeLast();

    return instances[typeName];
  }

 
  // PUBLIC API
  dynamic get(Type type) {
    return _getInstanceByTypeName(type.toString()).reflectee;
  }
}
