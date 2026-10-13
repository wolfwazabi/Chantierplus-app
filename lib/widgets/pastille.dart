import 'package:flutter/material.dart';

/// Pastille rouge avec un nombre (rien si zéro) : « il y a N nouveautés ».
class PastilleNombre extends StatelessWidget {
  final int nombre;
  final String? libelle;

  const PastilleNombre(this.nombre, {super.key, this.libelle});

  @override
  Widget build(BuildContext context) {
    if (nombre <= 0) return const SizedBox.shrink();
    return Semantics(
      label: libelle ?? (nombre == 1 ? '1 nouveauté' : '$nombre nouveautés'),
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          nombre > 99 ? '99+' : '$nombre',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Petit point rouge à côté d'un changement nouveau.
class PointNouveau extends StatelessWidget {
  const PointNouveau({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Nouveau',
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
