import 'package:flutter/material.dart';

class Button extends StatefulWidget {
  final VoidCallback? onPressed;
  final String text;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? textColor;

  const Button({
    Key? key,
    required this.onPressed,
    required this.text,
    this.isLoading = false,
    this.backgroundColor,
    this.textColor,
  }) : super(key: key);

  @override
  State<Button> createState() => _ButtonState();
}

class _ButtonState extends State<Button> {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: widget.isLoading ? null : widget.onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        backgroundColor: widget.backgroundColor ?? Colors.white,
      ),
      child: widget.isLoading
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        widget.textColor ?? Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "Processing...",
                  style: TextStyle(
                    fontSize: 17,
                    color: widget.textColor ?? Colors.black,
                  ),
                ),
              ],
            )
          : Text(
              widget.text,
              style: TextStyle(
                fontSize: 17,
                color: widget.textColor ?? Colors.black,
              ),
            ),
    );
  }
}
