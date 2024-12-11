import 'package:flutter/material.dart';
import 'package:ftpconnect/ftpconnect.dart';

class TransferModeDropdown extends StatelessWidget {
  final TransferMode value;
  final Function(TransferMode?) onChanged;

  // ignore: use_super_parameters
  const TransferModeDropdown({
    Key? key,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<TransferMode>(
      value: value,
      items: const [
        DropdownMenuItem(
          value: TransferMode.active,
          child: Text('Active Mode'),
        ),
        DropdownMenuItem(
          value: TransferMode.passive,
          child: Text('Passive Mode'),
        ),
      ],
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: 'Select Transfer Mode',
        border: OutlineInputBorder(),
      ),
    );
  }
}
