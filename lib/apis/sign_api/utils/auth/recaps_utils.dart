import 'dart:convert';

import 'package:walletconnect_flutter_v2/apis/utils/errors.dart';

class ReCapsUtils {
  static String? getRecapFromResources({List<String>? resources}) {
    final resourcesList = resources ?? [];
    if (resourcesList.isEmpty) return null;
    // per spec, recap is always the last resource
    final recap = resourcesList.last;
    return isRecap(recap) ? recap : null;
  }

  static bool isRecap(String resource) {
    return resource.contains('urn:recap:');
  }

  static List<String> getMethodsFromRecap(String recap) {
    final decodedRecap = decodeRecap(recap);
    if (!isValidRecap(decodedRecap)) return [];

    try {
      // methods are only available for eip155 as per the current implementation
      final resource = decodedRecap['att']?['eip155'] as Map<String, dynamic>?;
      if (resource == null) return [];

      return resource.keys.map((k) => k.split('/').last).toList();
    } catch (e) {
      return [];
    }
  }

  static List<String> getChainsFromRecap(String recap) {
    final decodedRecap = decodeRecap(recap);
    if (!isValidRecap(decodedRecap)) return [];

    final List<dynamic> recapChains = [];
    try {
      final att =
          decodedRecap['att'] as Map<String, dynamic>? ?? <String, dynamic>{};

      for (var resources in att.values) {
        final resourcesMap = resources as Map<String, dynamic>;
        final resourcesValues = resourcesMap.values.first as List;
        for (var value in resourcesValues) {
          final chainValues = value as Map<String, dynamic>;
          final chains = chainValues['chains'] as List;
          recapChains.addAll(chains);
        }
      }
      return recapChains.map((e) => e.toString()).toSet().toList();
    } catch (e) {
      return [];
    }
  }

  static Map<String, dynamic> decodeRecap(String recap) {
    // Add the padding that was removed during encoding
    String paddedRecap = recap.replaceAll('urn:recap:', '');
    final padding = paddedRecap.length % 4;
    if (padding > 0) {
      paddedRecap += '=' * (4 - padding);
    }

    final decoded = utf8.decode(base64.decode(paddedRecap));
    final decodedRecap = jsonDecode(decoded) as Map<String, dynamic>;
    isValidRecap(decodedRecap);
    return decodedRecap;
  }

  static bool isValidRecap(Map<String, dynamic> recap) {
    final att = recap['att'] as Map<String, dynamic>?;
    if (att == null) {
      throw Errors.getInternalError(
        Errors.MISSING_OR_INVALID,
        context: 'Invalid ReCap. No `att` property found',
      );
    }
    //
    final resources = att.keys;
    if (resources.isEmpty) {
      throw Errors.getInternalError(
        Errors.MISSING_OR_INVALID,
        context: 'Invalid ReCap. No resources found in `att` property',
      );
    }
    //
    for (var resource in resources) {
      final abilities = att[resource];
      if (abilities is! Map) {
        throw Errors.getInternalError(
          Errors.MISSING_OR_INVALID,
          context: 'Invalid ReCap. Resource must be an object: $resource',
        );
      }
      final resourceAbilities = (abilities as Map<String, dynamic>).keys;
      if (resourceAbilities.isEmpty) {
        throw Errors.getInternalError(
          Errors.MISSING_OR_INVALID,
          context: 'Invalid ReCap. Resource object is empty: $resource',
        );
      }
      //
      for (var ability in resourceAbilities) {
        final limits = abilities[ability];
        if (limits is! List) {
          throw Errors.getInternalError(
            Errors.MISSING_OR_INVALID,
            context: 'Invalid ReCap. Ability limits $ability must be an array '
                'of objects, found: $limits',
          );
        }
        if ((limits).isEmpty) {
          throw Errors.getInternalError(
            Errors.MISSING_OR_INVALID,
            context: 'Invalid ReCap. Value of $ability is empty array, must be '
                'an array with objects',
          );
        }
        //
        for (var limit in limits) {
          if (limit is! Map) {
            throw Errors.getInternalError(
              Errors.MISSING_OR_INVALID,
              context:
                  'Invalid ReCap. Ability limits ($ability) must be an array '
                  'of objects, found: $limit',
            );
          }
        }
      }
    }

    return true;
  }

  static String createEncodedRecap(
    String namespace,
    String ability,
    List<String> methods,
  ) {
    final recap = createRecap(namespace, ability, methods);
    return encodeRecap(recap);
  }

  static String encodeRecap(Map<String, dynamic> recap) {
    isValidRecap(recap);
    final jsonRecap = jsonEncode(recap);
    final bytes = utf8.encode(jsonRecap).toList();
    // remove the padding from the base64 string as per recap spec
    return 'urn:recap:${base64.encode(bytes).replaceAll('/=/g', '')}';
  }

  static Map<String, dynamic> createRecap(
    String namespace,
    String ability,
    List<String> methods, {
    Map limits = const {},
  }) {
    try {
      final sortedMethods = List<String>.from(methods)
        ..sort((a, b) => a.compareTo(b));

      Map<String, dynamic> abilities = {};
      for (var method in sortedMethods) {
        abilities['$ability/$method'] = [
          ...(abilities['$ability/$method'] ?? []),
          limits,
        ];
      }

      return {
        'att': {
          namespace: Map<String, dynamic>.fromEntries(abilities.entries),
        }
      };
    } catch (e) {
      rethrow;
    }
  }

  static String mergeEncodedRecaps(String recap1, String recap2) {
    final decoded1 = decodeRecap(recap1);
    final decoded2 = decodeRecap(recap2);
    final merged = mergeRecaps(decoded1, decoded2);
    return encodeRecap(merged);
  }

  static Map<String, dynamic> mergeRecaps(
    Map<String, dynamic> recap1,
    Map<String, dynamic> recap2,
  ) {
    isValidRecap(recap1);
    isValidRecap(recap2);
    final att1 = recap1['att'] as Map<String, dynamic>;
    final att2 = recap2['att'] as Map<String, dynamic>;
    final keys = [...att1.keys, ...att2.keys]..sort(
        (a, b) => a.compareTo(b),
      );
    final mergedRecap = {'att': {}};

    for (var key in keys) {
      final actions1 = att1[key] as Map<String, dynamic>? ?? {};
      final actions1Keys = actions1.keys;
      final actions2 = att2[key] as Map<String, dynamic>? ?? {};
      final actions2Keys = actions2.keys;
      final actions = [...actions1Keys, ...actions2Keys]..sort(
          (a, b) => a.compareTo(b),
        );

      for (var action in actions) {
        mergedRecap['att']![key] = {
          ...mergedRecap['att']?[key],
          [action]: recap1['att'][key]?[action] || recap2['att'][key]?[action],
        };
      }
    }

    return mergedRecap;
  }
}
