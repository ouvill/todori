import 'dart:io';

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

const _revenueCatApiKey = String.fromEnvironment(
  'TASKVEIL_REVENUECAT_IOS_API_KEY',
);
const _revenueCatEnvironment = String.fromEnvironment(
  'TASKVEIL_REVENUECAT_ENVIRONMENT',
);

enum BillingPurchaseOutcome { purchased, cancelled, pending, failed }

class BillingProduct {
  const BillingProduct({
    required this.identifier,
    required this.title,
    required this.description,
    required this.price,
    required this.isAnnual,
  });

  final String identifier;
  final String title;
  final String description;
  final String price;
  final bool isAnnual;
}

abstract interface class BillingStore {
  Future<void> configure({
    required String appUserId,
    required String environment,
  });

  Future<List<BillingProduct>> products();

  Future<BillingPurchaseOutcome> purchase(String productIdentifier);

  Future<BillingPurchaseOutcome> restore();

  Future<Uri?> managementUrl();

  /// RevenueCat logout is intentionally not called because it creates an
  /// anonymous customer. The next Taskveil login switches to the server-issued
  /// custom App User ID with [Purchases.logIn].
  Future<void> accountLoggedOut();
}

class RevenueCatBillingStore implements BillingStore {
  Package? _monthly;
  Package? _annual;

  @override
  Future<void> configure({
    required String appUserId,
    required String environment,
  }) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('iOS billing only');
    }
    if (_revenueCatApiKey.isEmpty ||
        _revenueCatEnvironment.isEmpty ||
        _revenueCatEnvironment != environment) {
      throw StateError('RevenueCat build configuration mismatch');
    }
    if (await Purchases.isConfigured) {
      if (await Purchases.appUserID != appUserId) {
        await Purchases.logIn(appUserId);
      }
      return;
    }
    final configuration = PurchasesConfiguration(_revenueCatApiKey)
      ..appUserID = appUserId
      ..automaticDeviceIdentifierCollectionEnabled = false;
    await Purchases.configure(configuration);
  }

  @override
  Future<List<BillingProduct>> products() async {
    final offering = (await Purchases.getOfferings()).getOffering('default');
    if (offering == null) return const [];
    _monthly = offering.availablePackages.where(_isMonthly).firstOrNull;
    _annual = offering.availablePackages.where(_isAnnual).firstOrNull;
    return [
      if (_monthly case final package?) _product(package, isAnnual: false),
      if (_annual case final package?) _product(package, isAnnual: true),
    ];
  }

  @override
  Future<BillingPurchaseOutcome> purchase(String productIdentifier) async {
    final package = [_monthly, _annual]
        .whereType<Package>()
        .where(
          (candidate) => candidate.storeProduct.identifier == productIdentifier,
        )
        .firstOrNull;
    if (package == null) return BillingPurchaseOutcome.failed;
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      return BillingPurchaseOutcome.purchased;
    } on PlatformException catch (error) {
      return _purchaseError(error);
    }
  }

  @override
  Future<BillingPurchaseOutcome> restore() async {
    try {
      await Purchases.restorePurchases();
      return BillingPurchaseOutcome.purchased;
    } on PlatformException catch (error) {
      return _purchaseError(error);
    }
  }

  @override
  Future<Uri?> managementUrl() async {
    final value = (await Purchases.getCustomerInfo()).managementURL;
    return value == null ? null : Uri.tryParse(value);
  }

  @override
  Future<void> accountLoggedOut() async {
    _monthly = null;
    _annual = null;
  }

  static BillingProduct _product(Package package, {required bool isAnnual}) {
    final product = package.storeProduct;
    return BillingProduct(
      identifier: product.identifier,
      title: product.title,
      description: product.description,
      price: product.priceString,
      isAnnual: isAnnual,
    );
  }

  static bool _isMonthly(Package package) =>
      package.storeProduct.identifier == 'com.taskveil.app.pro.monthly';

  static bool _isAnnual(Package package) =>
      package.storeProduct.identifier == 'com.taskveil.app.pro.yearly';

  static BillingPurchaseOutcome _purchaseError(PlatformException error) {
    return switch (PurchasesErrorHelper.getErrorCode(error)) {
      PurchasesErrorCode.purchaseCancelledError =>
        BillingPurchaseOutcome.cancelled,
      PurchasesErrorCode.paymentPendingError => BillingPurchaseOutcome.pending,
      _ => BillingPurchaseOutcome.failed,
    };
  }
}
