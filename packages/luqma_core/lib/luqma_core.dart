/// Shared foundation for the three Luqma apps.
///
/// Phase 0 ships the brand layer: colour, type, spacing, motion, the two themes, and the
/// logo lockup. Models, repositories and `RemoteConfigService` land in Phase 1.
library;

export 'src/app/emulator.dart';
export 'src/app/firebase_options.dart';
export 'src/auth/auth_service.dart';
export 'src/auth/staff_identity.dart';
export 'src/config/luqma_config.dart';
export 'src/config/remote_config_service.dart';
export 'src/l10n/app_localizations.dart';
export 'src/l10n/money.dart';
export 'src/models/billing.dart';
export 'src/models/converters.dart';
export 'src/models/coupon.dart';
export 'src/models/daily_meal.dart';
export 'src/models/geography.dart';
export 'src/models/home_section.dart';
export 'src/models/landmark_suggestion.dart';
export 'src/models/merchant.dart';
export 'src/models/media.dart';
export 'src/models/menu_item.dart';
export 'src/models/money.dart';
export 'src/models/order.dart';
export 'src/models/promotion.dart';
export 'src/models/revenue.dart';
export 'src/providers/providers.dart';
export 'src/repositories/address_repository.dart';
export 'src/repositories/billing_repository.dart';
export 'src/repositories/courier_order_repository.dart';
export 'src/repositories/daily_meal_repository.dart';
export 'src/repositories/feedback_repository.dart';
export 'src/repositories/geography_repository.dart';
export 'src/repositories/home_section_repository.dart';
export 'src/repositories/media_repository.dart';
export 'src/repositories/menu_repository.dart';
export 'src/repositories/merchant_order_repository.dart';
export 'src/repositories/order_repository.dart';
export 'src/repositories/promotion_repository.dart';
export 'src/repositories/merchant_repository.dart';
export 'src/result.dart';
export 'src/theme/colors.dart';
export 'src/theme/dimens.dart';
export 'src/theme/luqma_theme.dart';
export 'src/theme/motion.dart';
export 'src/theme/typography.dart';
export 'src/util/arabic_digits.dart';
export 'src/util/arabic_text.dart';
export 'src/util/contrast.dart';
export 'src/data/column_names.dart';
export 'src/widgets/address_picker.dart';
export 'src/widgets/error_view.dart';
export 'src/widgets/luqma_lockup.dart';
export 'src/widgets/menu_editor.dart';
export 'src/widgets/luqma_splash.dart';
