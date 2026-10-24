import 'package:flutter/material.dart';

import '../../core/design/app_theme.dart';

import '../../core/network/workspace_api.dart';

class EditField {
  final String keyName, label;
  final bool required, numeric, multiple, multiline, date, secret;
  final Map<String, String>? choices;
  final Map<String, Map<String, String?>>? selectionDefaults;
  final Map<String, String>? selectionHints;
  const EditField(
    this.keyName,
    this.label, {
    this.required = false,
    this.numeric = false,
    this.multiple = false,
    this.multiline = false,
    this.date = false,
    this.secret = false,
    this.choices,
    this.selectionDefaults,
    this.selectionHints,
  });
}

Future<Record?> showEditor(
  BuildContext context, {
  required String title,
  required List<EditField> fields,
  Record initial = const {},
  required Future<void> Function(Record) save,
}) {
  if (MediaQuery.sizeOf(context).width < 600) {
    return showModalBottomSheet<Record>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _Editor(
        title: title,
        fields: fields,
        initial: initial,
        save: save,
        sheet: true,
      ),
    );
  }
  return showDialog<Record>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _Editor(title: title, fields: fields, initial: initial, save: save),
  );
}

class _Editor extends StatefulWidget {
  final String title;
  final bool sheet;
  final List<EditField> fields;
  final Record initial;
  final Future<void> Function(Record) save;
  const _Editor({
    required this.title,
    this.sheet = false,
    required this.fields,
    required this.initial,
    required this.save,
  });
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _choices = {};
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      var value = widget.initial[field.keyName];
      if (field.choices != null) {
        _choices[field.keyName] = field.multiple
            ? List<String>.from((value as List? ?? []).map((e) => '$e'))
            : value?.toString();
      } else {
        if (field.date && value != null) value = '$value'.split('T').first;
        _controllers[field.keyName] = TextEditingController(
          text: value?.toString() ?? '',
        );
      }
    }
    for (final field in widget.fields) {
      final defaults = field.selectionDefaults?[_choices[field.keyName]];
      if (defaults == null) continue;
      for (final entry in defaults.entries) {
        if (!widget.initial.containsKey(entry.key)) {
          _choices[entry.key] = entry.value;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{};
      for (final field in widget.fields) {
        final value = field.choices != null
            ? _choices[field.keyName]
            : field.secret
            ? _controllers[field.keyName]!.text
            : _controllers[field.keyName]!.text.trim();
        if (field.multiple) {
          body[field.keyName] = (value as List)
              .map((e) => field.numeric ? int.parse('$e') : e)
              .toList();
        } else if (value != null && '$value'.isNotEmpty) {
          body[field.keyName] = field.choices != null && value == 'true'
              ? true
              : field.choices != null && value == 'false'
              ? false
              : field.numeric
              ? int.parse('$value')
              : value;
        } else if (field.date && widget.initial.containsKey(field.keyName)) {
          body[field.keyName] = null;
        } else if (!field.required &&
            !field.numeric &&
            field.choices == null &&
            widget.initial.containsKey(field.keyName)) {
          body[field.keyName] = field.keyName == 'amount' ? null : '';
        }
      }
      await widget.save(body);
      if (mounted) Navigator.pop(context, body);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final field in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _field(field),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
    final actions = [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'Saving…' : 'Save changes'),
      ),
    ];
    if (!widget.sheet) {
      return AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: fields),
        ),
        actions: actions,
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.sizeOf(context).height * .9 -
                      MediaQuery.viewInsetsOf(context).bottom)
                  .clamp(160, 900),
        ),
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
        decoration: const BoxDecoration(
          color: Color(0xFFFCFAFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.line,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 22),
              Flexible(child: SingleChildScrollView(child: fields)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [actions[0], const SizedBox(width: 10), actions[1]],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(EditField field) {
    if (field.choices != null && field.multiple) {
      final selected = _choices[field.keyName] as List<String>;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (field.choices!.isEmpty)
            const Text('No eligible options available.'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in field.choices!.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: selected.contains(entry.key),
                  onSelected: _busy
                      ? null
                      : (value) => setState(() {
                          value
                              ? selected.add(entry.key)
                              : selected.remove(entry.key);
                        }),
                ),
            ],
          ),
        ],
      );
    }
    if (field.choices != null) {
      final selected = _choices[field.keyName];
      return DropdownButtonFormField<String>(
        key: ValueKey('${field.keyName}:$selected'),
        initialValue: field.choices!.containsKey(selected)
            ? selected as String?
            : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.selectionHints?[selected],
          helperMaxLines: 3,
        ),
        items: field.choices!.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: _busy
            ? null
            : (value) => setState(() {
                final changed = _choices[field.keyName] != value;
                _choices[field.keyName] = value;
                final defaults = changed
                    ? (field.selectionDefaults?[value])
                    : null;
                if (defaults != null) _choices.addAll(defaults);
              }),
        validator: (v) => field.required && v == null
            ? 'Choose ${field.label.toLowerCase()}'
            : null,
      );
    }
    return TextFormField(
      controller: _controllers[field.keyName],
      obscureText: field.secret,
      maxLines: field.multiline ? 3 : 1,
      keyboardType: field.numeric ? TextInputType.number : null,
      readOnly: field.date,
      decoration: InputDecoration(
        labelText: field.label,
        suffixIcon: field.date
            ? IconButton(
                tooltip: 'Choose date',
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDate:
                        DateTime.tryParse(_controllers[field.keyName]!.text) ??
                        DateTime.now(),
                  );
                  if (date != null) {
                    _controllers[field.keyName]!.text = date
                        .toIso8601String()
                        .split('T')
                        .first;
                  }
                },
              )
            : null,
      ),
      validator: (v) {
        if (field.required && (v == null || v.trim().isEmpty)) {
          return '${field.label} is required';
        }
        if (field.numeric &&
            v != null &&
            v.isNotEmpty &&
            int.tryParse(v) == null) {
          return 'Enter a whole number';
        }
        return null;
      },
    );
  }
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;
