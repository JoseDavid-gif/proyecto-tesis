import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bache_model.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<Map<String, dynamic>> _cargarEstadisticas(String email) async {
    final response = await Supabase.instance.client
        .from('baches')
        .select('severidad, fecha, foto_url, area_cm2, metodo_medicion')
        .eq('usuario_email', email)
        .order('fecha', ascending: false);

    final List data = response as List;

    final total = data.length;
    final leves = data.where((b) => b['severidad'] == 'Leve').length;
    final moderados = data.where((b) => b['severidad'] == 'Moderado').length;
    final severos = data.where((b) => b['severidad'] == 'Severo').length;
    final noDeterminados =
        data.where((b) => b['severidad'] == 'No determinada').length;

    final conFoto = data.where((b) {
      final foto = b['foto_url'];
      return foto != null && foto.toString().trim().isNotEmpty;
    }).length;

    final conAruco =
        data.where((b) => b['metodo_medicion'] == Bache.metodoAruco).length;
    final conArCore = data
        .where((b) => b['metodo_medicion'] == Bache.metodoArCoreDepth)
        .length;

    double areaTotal = 0;
    for (final b in data) {
      final area = b['area_cm2'];
      final metodo = b['metodo_medicion'];
      if (area is num &&
          (metodo == Bache.metodoAruco || metodo == Bache.metodoArCoreDepth)) {
        areaTotal += area.toDouble();
      }
    }

    final ultimoReporte = data.isNotEmpty ? data.first['fecha'] : null;

    return {
      'total': total,
      'leves': leves,
      'moderados': moderados,
      'severos': severos,
      'noDeterminados': noDeterminados,
      'conFoto': conFoto,
      'conAruco': conAruco,
      'conArCore': conArCore,
      'conMedicion': conAruco + conArCore,
      'areaTotal': areaTotal,
      'ultimoReporte': ultimoReporte,
    };
  }

  String _obtenerNombreUsuario(String? email) {
    if (email == null || email.isEmpty) return 'Usuario';
    return email.split('@').first;
  }

  String _formatearFecha(dynamic fecha) {
    if (fecha == null) return 'Sin reportes';

    try {
      final date = DateTime.parse(fecha.toString());
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return fecha.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Usuario';
    final nombreUsuario = _obtenerNombreUsuario(user?.email);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey.shade100,
      body: user == null
          ? const Center(
              child: Text('No hay usuario autenticado'),
            )
          : FutureBuilder<Map<String, dynamic>>(
              future: _cargarEstadisticas(email),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.orange),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error cargando perfil: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                final stats = snapshot.data ?? {};

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const CircleAvatar(
                              radius: 52,
                              backgroundColor: Colors.orange,
                              child: Icon(
                                Icons.person,
                                size: 55,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              nombreUsuario,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: const Text(
                                'Reportero ciudadano Spothole',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              icon: Icons.warning_amber,
                              title: 'Reportes',
                              value: '${stats['total'] ?? 0}',
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard(
                              icon: Icons.image,
                              title: 'Con foto',
                              value: '${stats['conFoto'] ?? 0}',
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              icon: Icons.straighten,
                              title: 'Con medición',
                              value: '${stats['conMedicion'] ?? 0}',
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard(
                              icon: Icons.view_in_ar_outlined,
                              title: 'ARCore / ArUco',
                              value: '${stats['conArCore'] ?? 0} / '
                                  '${stats['conAruco'] ?? 0}',
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              icon: Icons.crop_square,
                              title: 'Suma de áreas bbox',
                              value:
                                  '${(stats['areaTotal'] ?? 0).toStringAsFixed(1)} cm²',
                              color: Colors.purple,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Resumen por severidad',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _severityRow(
                              label: 'Leves',
                              value: stats['leves'] ?? 0,
                              color: Colors.green,
                            ),
                            _severityRow(
                              label: 'Moderados',
                              value: stats['moderados'] ?? 0,
                              color: Colors.orange,
                            ),
                            _severityRow(
                              label: 'Severos',
                              value: stats['severos'] ?? 0,
                              color: Colors.red,
                            ),
                            _severityRow(
                              label: 'No determinados',
                              value: stats['noDeterminados'] ?? 0,
                              color: Colors.blueGrey,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_month,
                              color: Colors.orange,
                              size: 32,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Último reporte',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatearFecha(stats['ultimoReporte']),
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await Supabase.instance.client.auth.signOut();

                            if (context.mounted) {
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                                (_) => false,
                              );
                            }
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text('Cerrar sesión'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _severityRow({
    required String label,
    required int value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 6,
            backgroundColor: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label),
          ),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
