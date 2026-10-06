import 'package:flutter/material.dart';

import '../charpente/assistant_charpente.dart';
import '../charpente/charpente_screen.dart';
import '../charpente/ecran_escalier.dart';
import 'calcul_materiaux.dart';

/// Onglet « Calcul » d'un chantier : calcul de feuilles (simple), calcul de
/// charpente (plancher, murs, vue 3D, commande) et calcul des limons d'escalier.
class CalculChantier extends StatefulWidget {
  final String companyId;
  final String chantierId;
  final bool connecte;

  /// Remplace la liste des commandes enregistrées (tests, sans Firestore).
  @visibleForTesting
  final Widget? listeEnregistrees;

  /// Remplace l'appel au serveur de l'assistant (tests).
  @visibleForTesting
  final AppelAssistant appelAssistant;

  const CalculChantier({
    super.key,
    required this.companyId,
    required this.chantierId,
    required this.connecte,
    this.listeEnregistrees,
    this.appelAssistant = appelAssistantParDefaut,
  });

  @override
  State<CalculChantier> createState() => _CalculChantierState();
}

class _CalculChantierState extends State<CalculChantier>
    with AutomaticKeepAliveClientMixin {
  int _mode = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<int>(
            key: const ValueKey('calcul_mode'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.calculate_outlined),
                label: Text('Feuilles'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.architecture),
                label: Text('Charpente'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.stairs_outlined),
                label: Text('Escalier'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _mode,
            children: [
              const CalculMateriaux(),
              CharpenteScreen(
                companyId: widget.companyId,
                chantierId: widget.chantierId,
                connecte: widget.connecte,
                listeEnregistrees: widget.listeEnregistrees,
                appelAssistant: widget.appelAssistant,
              ),
              const EcranEscalier(),
            ],
          ),
        ),
      ],
    );
  }
}
