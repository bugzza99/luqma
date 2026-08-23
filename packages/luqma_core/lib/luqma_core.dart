/// Shared foundation for the three Luqma apps.
///
/// Phase 0 ships the brand layer: colour, type, spacing, motion, the two themes, and the
/// logo lockup. Models, repositories and `RemoteConfigService` land in Phase 1.
library;

export 'src/config/luqma_config.dart';
export 'src/config/remote_config_service.dart';
export 'src/l10n/app_localizations.dart';
export 'src/l10n/money.dart';
export 'src/models/converters.dart';
export 'src/models/coupon.dart';
export 'src/models/geography.dart';
export 'src/models/merchant.dart';
export 'src/models/menu_item.dart';
export 'src/models/money.dart';
export 'src/models/order.dart';
export 'src/providers/providers.dart';
export 'src/repositories/geography_repository.dart';
export 'src/repositories/menu_repository.dart';
export 'src/repositories/merchant_repository.dart';
export 'src/result.dart';
export 'src/theme/colors.dart';
export 'src/theme/dimens.dart';
export 'src/theme/luqma_theme.dart';
export 'src/theme/motion.dart';
export 'src/theme/typography.dart';
export 'src/util/arabic_digits.dart';
export 'src/util/contrast.dart';
export 'src/widgets/address_picker.dart';
export 'src/widgets/luqma_lockup.dart';
export 'src/widgets/menu_editor.dart';
export 'src/widgets/luqma_splash.dart';
