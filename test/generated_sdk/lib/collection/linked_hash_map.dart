// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of dart.collection;

/**
 * A hash-table based implementation of [Map].
 *
 * The insertion order of keys is remembered,
 * and keys are iterated in the order they were inserted into the map.
 * Values are iterated in their corresponding key's order.
 * Changing a key's value, when the key is already in the map,
 * does not change the iteration order,
 * but removing the key and adding it again
 * will make it be last in the iteration order.
 *
 * The keys of a `LinkedHashMap` must have consistent [Object.operator==]
 * and [Object.hashCode] implementations. This means that the `==` operator
 * must define a stable equivalence relation on the keys (reflexive,
 * symmetric, transitive, and consistent over time), and that `hashCode`
 * must be the same for objects that are considered equal by `==`.
 *
 * The map allows `null` as a key.
 */
abstract class LinkedHashMap<K, V> implements HashMap<K, V> {
  @patch
  factory LinkedHashMap({ bool equals(K key1, K key2),
                          int hashCode(K key),
                          bool isValidKey(potentialKey) }) {
    if (isValidKey == null) {
      if (hashCode == null) {
        if (equals == null) {
          return new _LinkedHashMap<K, V>();
        }
        hashCode = _defaultHashCode;
      } else {
        if (identical(identityHashCode, hashCode) &&
            identical(identical, equals)) {
          return new _LinkedIdentityHashMap<K, V>();
        }
        if (equals == null) {
          equals = _defaultEquals;
        }
      }
    } else {
      if (hashCode == null) {
        hashCode = _defaultHashCode;
      }
      if (equals == null) {
        equals = _defaultEquals;
      }
    }
    return new _LinkedCustomHashMap<K, V>(equals, hashCode, isValidKey);
  }

  @patch
  factory LinkedHashMap.identity() = _LinkedIdentityHashMap<K, V>;

  /**
   * Creates a [LinkedHashMap] that contains all key value pairs of [other].
   */
  factory LinkedHashMap.from(Map other) {
    LinkedHashMap<K, V> result = new LinkedHashMap<K, V>();
    other.forEach((k, v) { result[k] = v; });
    return result;
  }

  /**
   * Creates a [LinkedHashMap] where the keys and values are computed from the
   * [iterable].
   *
   * For each element of the [iterable] this constructor computes a key/value
   * pair, by applying [key] and [value] respectively.
   *
   * The keys of the key/value pairs do not need to be unique. The last
   * occurrence of a key will simply overwrite any previous value.
   *
   * If no values are specified for [key] and [value] the default is the
   * identity function.
   */
  factory LinkedHashMap.fromIterable(Iterable iterable,
      {K key(element), V value(element)}) {
    LinkedHashMap<K, V> map = new LinkedHashMap<K, V>();
    Maps._fillMapWithMappedIterable(map, iterable, key, value);
    return map;
  }

  /**
   * Creates a [LinkedHashMap] associating the given [keys] to [values].
   *
   * This constructor iterates over [keys] and [values] and maps each element of
   * [keys] to the corresponding element of [values].
   *
   * If [keys] contains the same object multiple times, the last occurrence
   * overwrites the previous value.
   *
   * It is an error if the two [Iterable]s don't have the same length.
   */
  factory LinkedHashMap.fromIterables(Iterable<K> keys, Iterable<V> values) {
    LinkedHashMap<K, V> map = new LinkedHashMap<K, V>();
    Maps._fillMapWithIterables(map, keys, values);
    return map;
  }
}