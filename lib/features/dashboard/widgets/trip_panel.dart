import 'package:flutter/material.dart';
import '../../../services/trip_calculator.dart';

class TripPanel extends StatelessWidget {
  final TripCalculator calculator;
  final VoidCallback onReset;

  const TripPanel({
    super.key,
    required this.calculator,
    required this.onReset,
  });

  void _showDetailsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Статистика поездки', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _buildDetailRow(context, 'Потрачено топлива:', '${calculator.totalFuelLiters.toStringAsFixed(2)} л'),
              _buildDetailRow(context, 'Максимальная скорость:', '${calculator.maxSpeedKmh.toStringAsFixed(1)} км/ч'),
              _buildDetailRow(context, 'Средний расход:', '${calculator.averageConsumptionL100Km.toStringAsFixed(1)} л/100км'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    onReset();
                    Navigator.pop(context);
                  },
                  child: const Text('Сбросить поездку', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetailsSheet(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13), // ~0.05 opacity
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatBlock(context, Icons.route, '${calculator.totalDistanceKm.toStringAsFixed(1)} км'),
            Container(width: 1, height: 24, color: Theme.of(context).dividerColor),
            _buildStatBlock(context, Icons.local_gas_station, '${calculator.averageConsumptionL100Km.toStringAsFixed(1)} л'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBlock(BuildContext context, IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono')),
      ],
    );
  }
}