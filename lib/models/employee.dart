enum EmployeeRole { admin, plus, employe }

class Employee {
  final String id;
  final String? companyId;
  final String? companyNom;
  final String nom;
  final EmployeeRole role;
  final bool estProprietaire;
  final bool estSuperAdmin;
  final bool estIndividuel;

  Employee({
    required this.id,
    required this.companyId,
    required this.companyNom,
    required this.nom,
    required this.role,
    this.estProprietaire = false,
    this.estSuperAdmin = false,
    this.estIndividuel = false,
  });

  static EmployeeRole roleFromString(String? s) {
    switch (s) {
      case 'admin':
        return EmployeeRole.admin;
      case 'plus':
        return EmployeeRole.plus;
      default:
        return EmployeeRole.employe;
    }
  }
}