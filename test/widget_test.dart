import 'package:flutter_test/flutter_test.dart';
import 'package:construction_app/models/employee.dart';

void main() {
  group('Employee.roleFromString', () {
    test('reconnaît les rôles connus', () {
      expect(Employee.roleFromString('admin'), EmployeeRole.admin);
      expect(Employee.roleFromString('plus'), EmployeeRole.plus);
      expect(Employee.roleFromString('employe'), EmployeeRole.employe);
    });

    test('rôle inconnu ou absent → employé (moindre privilège)', () {
      expect(Employee.roleFromString('superadmin'), EmployeeRole.employe);
      expect(Employee.roleFromString(null), EmployeeRole.employe);
    });
  });
}
