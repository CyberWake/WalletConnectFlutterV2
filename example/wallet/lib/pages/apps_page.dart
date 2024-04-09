import 'package:fl_toast/fl_toast.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:get_it_mixin/get_it_mixin.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:walletconnect_flutter_v2_wallet/dependencies/bottom_sheet/i_bottom_sheet_service.dart';
import 'package:walletconnect_flutter_v2_wallet/dependencies/deep_link_handler.dart';
import 'package:walletconnect_flutter_v2_wallet/dependencies/i_web3wallet_service.dart';
import 'package:walletconnect_flutter_v2_wallet/pages/app_detail_page.dart';
import 'package:walletconnect_flutter_v2_wallet/utils/constants.dart';
import 'package:walletconnect_flutter_v2_wallet/utils/string_constants.dart';
import 'package:walletconnect_flutter_v2_wallet/widgets/pairing_item.dart';
import 'package:walletconnect_flutter_v2_wallet/widgets/qr_scan_sheet.dart';
import 'package:walletconnect_flutter_v2_wallet/widgets/uri_input_popup.dart';

class AppsPage extends StatefulWidget with GetItStatefulWidgetMixin {
  AppsPage({Key? key}) : super(key: key);

  @override
  AppsPageState createState() => AppsPageState();
}

class AppsPageState extends State<AppsPage> with GetItStateMixin {
  List<PairingInfo> _pairings = [];
  late IWeb3WalletService _web3walletService;
  late IWeb3Wallet _web3Wallet;

  @override
  void initState() {
    super.initState();
    _web3walletService = GetIt.I<IWeb3WalletService>();
    _web3Wallet = _web3walletService.web3wallet;
    _pairings = _web3Wallet.pairings.getAll();
    _pairings = _pairings.where((p) => p.active).toList();
    _web3Wallet.core.relayClient.onRelayClientMessage.subscribe(_updateState);
    _web3Wallet.onSessionProposal.subscribe(_updateState);
    _web3Wallet.onSessionProposalError.subscribe(_updateState);
    _web3Wallet.onSessionDelete.subscribe(_updateState);
    // TODO web3Wallet.core.echo.register(firebaseAccessToken);
    DeepLinkHandler.onLink.listen(_onFoundUri);
    DeepLinkHandler.checkInitialLink();
  }

  @override
  void dispose() {
    _web3Wallet.onSessionProposal.unsubscribe(_updateState);
    _web3Wallet.onSessionProposalError.unsubscribe(_updateState);
    _web3Wallet.onSessionDelete.unsubscribe(_updateState);
    _web3Wallet.core.relayClient.onRelayClientMessage.unsubscribe(_updateState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // _pairings = (watch(target: GetIt.I<IWeb3WalletService>().pairings));
    // _pairings = _pairings.where((p) => p.active).toList();
    return Stack(
      children: [
        _pairings.isEmpty ? _buildNoPairingMessage() : _buildPairingList(),
        Positioned(
          bottom: StyleConstants.magic20,
          right: StyleConstants.magic20,
          child: Row(
            children: [
              const SizedBox(width: StyleConstants.magic20),
              _buildIconButton(Icons.copy, _onCopyQrCode),
              const SizedBox(width: StyleConstants.magic20),
              _buildIconButton(Icons.qr_code_rounded, _onScanQrCode),
            ],
          ),
        ),
        ValueListenableBuilder(
          valueListenable: DeepLinkHandler.waiting,
          builder: (context, value, _) {
            return Visibility(
              visible: value,
              child: Center(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.all(Radius.circular(50.0)),
                  ),
                  padding: const EdgeInsets.all(12.0),
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNoPairingMessage() {
    return const Center(
      child: Text(
        StringConstants.noApps,
        textAlign: TextAlign.center,
        style: StyleConstants.bodyText,
      ),
    );
  }

  Widget _buildPairingList() {
    final pairingItems = _pairings
        .map(
          (PairingInfo pairing) => PairingItem(
            key: ValueKey(pairing.topic),
            pairing: pairing,
            onTap: () => _onListItemTap(pairing),
          ),
        )
        .toList();

    return ListView.builder(
      itemCount: pairingItems.length,
      itemBuilder: (BuildContext context, int index) {
        return pairingItems[index];
      },
    );
  }

  Widget _buildIconButton(IconData icon, void Function()? onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: StyleConstants.primaryColor,
        borderRadius: BorderRadius.circular(
          StyleConstants.linear48,
        ),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: StyleConstants.titleTextColor,
        ),
        iconSize: StyleConstants.linear24,
        onPressed: onPressed,
      ),
    );
  }

  Future<dynamic> _onCopyQrCode() async {
    final uri = await GetIt.I<IBottomSheetService>().queueBottomSheet(
      widget: UriInputPopup(),
    );
    if (uri is String) {
      _onFoundUri(uri);
    }
  }

  Future _onScanQrCode() async {
    final scannedValue = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext modalContext) {
        return QRScanSheet(
          title: StringConstants.scanPairing,
        );
      },
    );

    _onFoundUri(scannedValue);
  }

  Future<void> _onFoundUri(String? uri) async {
    try {
      DeepLinkHandler.waiting.value = true;
      final Uri uriData = Uri.parse(uri!);
      await _web3Wallet.pair(uri: uriData);
    } catch (e) {
      showToast(
        child: Container(
          padding: const EdgeInsets.all(StyleConstants.linear8),
          margin: const EdgeInsets.only(
            bottom: StyleConstants.magic40,
          ),
          decoration: BoxDecoration(
            color: StyleConstants.errorColor,
            borderRadius: BorderRadius.circular(
              StyleConstants.linear16,
            ),
          ),
          child: const Text(
            StringConstants.invalidUri,
            style: StyleConstants.bodyTextBold,
          ),
        ),
        // ignore: use_build_context_synchronously
        context: context,
      );
    }
  }

  void _updateState(dynamic event) {
    setState(() {
      if (event is SessionProposalEvent) {
        DeepLinkHandler.waiting.value = true;
      }
      _pairings = _web3Wallet.pairings.getAll();
      _pairings = _pairings.where((p) => p.active).toList();
    });
  }

  void _onListItemTap(PairingInfo pairing) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AppDetailPage(
          pairing: pairing,
        ),
      ),
    );
  }
}
