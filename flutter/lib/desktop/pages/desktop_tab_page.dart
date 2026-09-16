import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/araquaridesk_auth.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../../common/shared_state.dart';

class DesktopTabPage extends StatefulWidget {
  const DesktopTabPage({Key? key}) : super(key: key);

  @override
  State<DesktopTabPage> createState() => _DesktopTabPageState();

  static void onAddSetting(
      {SettingsTabKey initialPage = SettingsTabKey.general}) {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelSettingPage,
          label: kTabLabelSettingPage,
          selectedIcon: Icons.build_sharp,
          unselectedIcon: Icons.build_outlined,
          page: DesktopSettingPage(
            key: const ValueKey(kTabLabelSettingPage),
            initialTabkey: initialPage,
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopTabPageState extends State<DesktopTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);
  final auth = AraquariDeskAuth.instance;

  _DesktopTabPageState() {
    RemoteCountState.init();
    Get.put<DesktopTabController>(tabController);
    tabController.add(TabInfo(
        key: kTabLabelHomePage,
        label: kTabLabelHomePage,
        selectedIcon: Icons.home_sharp,
        unselectedIcon: Icons.home_outlined,
        closable: false,
        page: const _AraquariDeskHomePageGate(
          key: ValueKey(kTabLabelHomePage),
        )));
    if (bind.isIncomingOnly()) {
      tabController.onSelected = (key) {
        if (key == kTabLabelHomePage) {
          windowManager.setSize(getIncomingOnlyHomeSize());
          setResizable(false);
        } else {
          windowManager.setSize(getIncomingOnlySettingsSize());
          setResizable(true);
        }
      };
    }
  }

  @override
  void initState() {
    super.initState();
    auth.addListener(_onAuthChanged);
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    await auth.initialize();
    if (!mounted) return;
    _applyWindowProfile();
  }

  void _onAuthChanged() {
    if (mounted) {
      setState(() {});
      _applyWindowProfile();
    }
  }

  Future<void> _applyWindowProfile() async {
    // The Rust process starts common users in incoming-only mode, so the base
    // RustDesk UI automatically hides the outgoing pane and uses the compact
    // layout. Admin processes are bidirectional and keep the full window.
    if (bind.isIncomingOnly()) {
      await windowManager.setSize(getIncomingOnlyHomeSize());
      setResizable(false);
    } else {
      await windowManager.setSize(const Size(960, 650));
      setResizable(true);
    }
  }

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    Get.delete<DesktopTabController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabWidget = Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: Stack(
              children: [
                Positioned.fill(
                  child: DesktopTab(
                    controller: tabController,
                    tail: Offstage(
                      offstage: bind.isIncomingOnly() ||
                          bind.isDisableSettings(),
                      child: ActionIcon(
                        message: 'Settings',
                        icon: IconFont.menu,
                        onTap: DesktopTabPage.onAddSetting,
                        isClose: false,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 42,
                  right: 16,
                  child: _RoleAccessButton(auth: auth),
                ),
              ],
            )));
    return isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => DragToResizeArea(
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: windowManagerEnableResizeEdges,
              child: tabWidget,
            ),
          );
  }
}

class _AraquariDeskHomePageGate extends StatelessWidget {
  const _AraquariDeskHomePageGate({super.key});

  @override
  Widget build(BuildContext context) {
    return const DesktopHomePage();
  }
}

class _RoleAccessButton extends StatelessWidget {
  const _RoleAccessButton({required this.auth});

  final AraquariDeskAuth auth;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        if (!auth.isAdmin) {
          return _accessButton(
            context,
            icon: Icons.lock_outline,
            label: auth.setupRequired ? 'Configurar TI' : 'Acesso da TI',
            onPressed: () => _showLogin(context),
          );
        }
        return PopupMenuButton<String>(
          tooltip: 'Modo TI',
          onSelected: (value) {
            if (value == 'users') {
              _showAdminManagement(context);
            } else if (value == 'logout') {
              _logout(context);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'users',
              child: Row(
                children: [
                  Icon(Icons.manage_accounts_outlined),
                  SizedBox(width: 10),
                  Text('Gerenciar TIs'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 10),
                  Text('Sair da TI'),
                ],
              ),
            ),
          ],
          child: _roleChip(
            context,
            icon: Icons.lock_open_outlined,
            label: 'Modo TI',
            subtitle: auth.currentAdmin?.displayName ??
                auth.currentAdmin?.username ??
                '',
          ),
        );
      },
    );
  }

  Widget _accessButton(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onPressed}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: _roleChip(context, icon: icon, label: label),
      ),
    );
  }

  Widget _roleChip(BuildContext context,
      {required IconData icon, required String label, String? subtitle}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.96),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.24),
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(blurRadius: 8, color: Colors.black12, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (subtitle != null && subtitle.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withOpacity(0.7),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showLogin(BuildContext context) async {
    final usernameController = TextEditingController(text: auth.setupRequired ? 'admin' : '');
    final displayController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final isSetup = auth.setupRequired;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            var busy = false;
            String? error;
            return AlertDialog(
              title: Text(isSetup ? 'Configurar acesso da TI' : 'Acesso da TI'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isSetup
                          ? 'Crie a conta mestre admin para habilitar o Modo TI.'
                          : 'Entre com seu usuário e senha de TI.',
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: usernameController,
                      enabled: !isSetup,
                      decoration: const InputDecoration(
                        labelText: 'Usuário',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    if (isSetup) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: displayController,
                        decoration: const InputDecoration(
                          labelText: 'Nome exibido',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: Icon(Icons.password_outlined),
                      ),
                    ),
                    if (isSetup) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: confirmController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar senha',
                          prefixIcon: Icon(Icons.password_outlined),
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          final password = passwordController.text;
                          if (password.length < 10) {
                            setState(() {
                              busy = false;
                              error = 'Use uma senha com pelo menos 10 caracteres.';
                            });
                            return;
                          }
                          if (isSetup && password != confirmController.text) {
                            setState(() {
                              busy = false;
                              error = 'As senhas não conferem.';
                            });
                            return;
                          }
                          if (isSetup) {
                            final ok = await auth.setupMaster(
                              password: password,
                              displayName: displayController.text.trim().isEmpty
                                  ? 'Administrador'
                                  : displayController.text.trim(),
                            );
                            if (!ok) {
                              setState(() {
                                busy = false;
                                error = 'Não foi possível criar a conta mestre.';
                              });
                              return;
                            }
                            if (context.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } else {
                            final account = await auth.login(
                                usernameController.text, password);
                            if (account == null) {
                              setState(() {
                                busy = false;
                                error = 'Usuário ou senha inválidos.';
                              });
                              return;
                            }
                            if (context.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          }
                        },
                  child: Text(isSetup ? 'Criar e entrar' : 'Entrar'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    displayController.dispose();
    passwordController.dispose();
    confirmController.dispose();

    if (result == true) {
      final account = auth.currentAdmin;
      final displayName = account?.displayName ?? 'Administrador';
      if (isSetup) {
        final account = await auth.login('admin', passwordController.text);
        if (account == null) return;
      }
      await _restartProcess(
        admin: true,
        displayName: displayName,
      );
    } else if (isSetup) {
      // The setup dialog creates the account but intentionally does not leave
      // the common process in an elevated state if the restart is cancelled.
      auth.logout();
    }
  }

  Future<void> _showAdminManagement(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final users = auth.admins;
          return AlertDialog(
            title: const Text('Administradores / TI'),
            content: SizedBox(
              width: 520,
              height: 360,
              child: ListView.separated(
                itemCount: users.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final user = users[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Icon(user.isMaster ? Icons.star : Icons.person),
                    ),
                    title: Text(user.displayName),
                    subtitle: Text(
                        '${user.username} · ${user.permissions.join(', ')}'),
                    trailing: user.isMaster
                        ? const Chip(label: Text('mestre'))
                        : PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'password') {
                                await _changePassword(context, user.username);
                              } else if (value == 'name') {
                                await _changeDisplayName(
                                    context, user.username, user.displayName);
                              } else if (value == 'delete') {
                                final ok = await auth.removeAdmin(user.username);
                                if (ok) setState(() {});
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'name',
                                child: Text('Alterar nome'),
                              ),
                              PopupMenuItem(
                                value: 'password',
                                child: Text('Alterar senha'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Remover'),
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  final created = await _addAdmin(context);
                  if (created) setState(() {});
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Adicionar TI'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fechar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _addAdmin(BuildContext context) async {
    final user = TextEditingController();
    final name = TextEditingController();
    final password = TextEditingController();
    final confirm = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicionar TI'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: user, decoration: const InputDecoration(labelText: 'Usuário')),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome exibido')),
              const SizedBox(height: 10),
              TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Senha')),
              const SizedBox(height: 10),
              TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmar senha')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (password.text.length < 10 || password.text != confirm.text) return;
              final ok = await auth.addAdmin(
                username: user.text,
                password: password.text,
                displayName: name.text.isEmpty ? user.text : name.text,
              );
              if (ok && dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    user.dispose();
    name.dispose();
    password.dispose();
    confirm.dispose();
    return result == true;
  }

  Future<void> _changePassword(BuildContext context, String username) async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Alterar senha · $username'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Nova senha')),
              const SizedBox(height: 10),
              TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmar senha')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (password.text.length < 10 || password.text != confirm.text) return;
              final ok = await auth.changePassword(username, password.text);
              if (ok && dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    password.dispose();
    confirm.dispose();
    if (result == true && mounted) setState(() {});
  }

  Future<void> _changeDisplayName(
      BuildContext context, String username, String currentName) async {
    final name = TextEditingController(text: currentName);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Alterar nome · $username'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Nome exibido'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final ok = await auth.updateDisplayName(username, name.text);
              if (ok && dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    name.dispose();
    if (result == true && mounted) setState(() {});
  }

  Future<void> _logout(BuildContext context) async {
    await _restartProcess(admin: false);
  }

  Future<void> _restartProcess({required bool admin, String? displayName}) async {
    final args = <String>[];
    if (admin) {
      args.add('--araquari-admin');
      args.add('--araquari-display-name=${displayName ?? 'Administrador'}');
    }
    await Process.start(
      Platform.resolvedExecutable,
      args,
      mode: ProcessStartMode.detached,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    exit(0);
  }
}
