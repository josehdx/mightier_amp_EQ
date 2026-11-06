// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const Duration _kMenuDuration = Duration(milliseconds: 300);
const double _kBaselineOffsetFromBottom = 20.0;
const double _kMenuCloseIntervalEnd = 2.0 / 3.0;
const double _kMenuHorizontalPadding = 0.0;
const double _kMenuItemHeight = 48.0;
const double _kMenuDividerHeight = 16.0;
const double _kMenuMaxWidth = 5.0 * _kMenuWidthStep;
const double _kMenuMinWidth = 2.0 * _kMenuWidthStep;
const double _kMenuVerticalPadding = 0.0; 
const double _kMenuWidthStep = 56.0;
const double _kMenuScreenPadding = 8.0;

abstract class PopupMenuEntry<T> extends StatefulWidget {
  const PopupMenuEntry({Key? key}) : super(key: key);
  double get height;
  bool represents(T value);
}

class LabeledDivider extends StatelessWidget {
  const LabeledDivider(
      {Key? key,
      this.height,
      this.thickness,
      this.indent,
      this.insideIndent,
      this.color,
      required this.text})
      : assert(height == null || height >= 0.0),
        assert(thickness == null || thickness >= 0.0),
        assert(indent == null || indent >= 0.0),
        assert(insideIndent == null || insideIndent >= 0.0),
        super(key: key);

  final double? height;
  final double? thickness;
  final double? indent;
  final double? insideIndent;
  final Color? color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final DividerThemeData dividerTheme = DividerTheme.of(context);
    final double height = this.height ?? dividerTheme.space ?? 16.0;
    final double thickness = this.thickness ?? dividerTheme.thickness ?? 1.0;
    final double indent = this.indent ?? dividerTheme.indent ?? 6.0;
    final double insideIndent =
        this.insideIndent ?? dividerTheme.endIndent ?? 4.0;

    return Container(
      color: Theme.of(context).popupMenuTheme.color,
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              margin:
                  EdgeInsetsDirectional.only(start: indent, end: insideIndent),
              height: thickness,
              color: color,
            ),
          ),
          Text(text, style: TextStyle(color: color)),
          Expanded(
            child: Container(
              margin:
                  EdgeInsetsDirectional.only(start: insideIndent, end: indent),
              height: thickness,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// FIX: Changed from <Null> to <dynamic> to prevent Dart TypeError crashes when dropdown seeks initial integer value
class PopupMenuDivider extends PopupMenuEntry<dynamic> {
  const PopupMenuDivider(
      {Key? key,
      this.height = _kMenuDividerHeight,
      required this.text,
      this.color})
      : super(key: key);

  @override
  final double height;
  final String text;
  final Color? color;

  @override
  bool represents(dynamic value) => false;

  @override
  State createState() => _PopupMenuDividerState();
}

class _PopupMenuDividerState extends State<PopupMenuDivider> {
  @override
  Widget build(BuildContext context) => LabeledDivider(
        color: widget.color,
        height: widget.height,
        text: widget.text,
      );
}

class PopupMenuItem<T> extends PopupMenuEntry<T> {
  const PopupMenuItem({
    Key? key,
    required this.value,
    this.enabled = true,
    this.height = _kMenuItemHeight,
    this.backgroundColor,
    required this.child,
  }) : super(key: key);

  final T value;
  final bool enabled;
  @override
  final double height;
  final Color? backgroundColor;
  final Widget child;

  @override
  bool represents(T value) => value == this.value;

  @override
  PopupMenuItemState<T, PopupMenuItem<T>> createState() =>
      PopupMenuItemState<T, PopupMenuItem<T>>();
}

class PopupMenuItemState<T, W extends PopupMenuItem<T>> extends State<W> {
  @protected
  Widget buildChild() => widget.child;

  @protected
  void handleTap() {
    Navigator.pop<T>(context, widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    TextStyle style = theme.textTheme.titleMedium!;
    if (!widget.enabled) style = style.copyWith(color: theme.disabledColor);

    Widget item = AnimatedDefaultTextStyle(
      style: style,
      duration: kThemeChangeDuration,
      child: Baseline(
        baseline: widget.height - _kBaselineOffsetFromBottom,
        baselineType: style.textBaseline!,
        child: buildChild(),
      ),
    );
    if (!widget.enabled) {
      final bool isDark = theme.brightness == Brightness.dark;
      item = IconTheme.merge(
        data: IconThemeData(opacity: isDark ? 0.5 : 0.38),
        child: item,
      );
    }

    return InkWell(
      onTap: widget.enabled ? handleTap : null,
      child: Container(
        color: widget.backgroundColor ?? Theme.of(context).popupMenuTheme.color,
        height: widget.height,
        padding:
            const EdgeInsets.symmetric(horizontal: _kMenuHorizontalPadding),
        child: item,
      ),
    );
  }
}

class CheckedPopupMenuItem<T> extends PopupMenuItem<T> {
  const CheckedPopupMenuItem({
    Key? key,
    required T value,
    this.checked = false,
    bool enabled = true,
    required Widget child,
  }) : super(
          key: key,
          value: value,
          enabled: enabled,
          child: child,
        );

  final bool checked;
  @override
  Widget get child => super.child;
  @override
  _CheckedPopupMenuItemState<T> createState() =>
      _CheckedPopupMenuItemState<T>();
}

class _CheckedPopupMenuItemState<T>
    extends PopupMenuItemState<T, CheckedPopupMenuItem<T>>
    with SingleTickerProviderStateMixin {
  static const Duration _fadeDuration = Duration(milliseconds: 150);
  late AnimationController _controller;
  Animation<double> get _opacity => _controller.view;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: _fadeDuration, vsync: this)
      ..value = widget.checked ? 1.0 : 0.0
      ..addListener(() => setState(() {/* animation changed */}));
  }

  @override
  void handleTap() {
    if (widget.checked) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    super.handleTap();
  }

  @override
  Widget buildChild() {
    return ListTile(
      enabled: widget.enabled,
      leading: FadeTransition(
        opacity: _opacity,
        child: Icon(_controller.isDismissed ? null : Icons.done),
      ),
      title: widget.child,
    );
  }
}

class _PopupMenu<T> extends StatelessWidget {
  const _PopupMenu({
    Key? key,
    required this.route,
    this.semanticLabel = "",
    this.controller,
  }) : super(key: key);

  final _PopupMenuRoute<T> route;
  final String semanticLabel;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final double unit = 1.0 /
        (route.items.length +
            1.5); 
    final List<Widget> children = <Widget>[];

    for (int i = 0; i < route.items.length; i += 1) {
      final double start = (i + 1) * unit;
      final double end = (start + 1.5 * unit).clamp(0.0, 1.0);
      final CurvedAnimation opacity = CurvedAnimation(
        parent: route.animation!,
        curve: Interval(start, end),
      );
      Widget item = route.items[i];
      if (route.initialValue != null &&
          route.items[i].represents(route.initialValue)) {
        item = ColoredBox(
          color: Theme.of(context).highlightColor,
          child: item,
        );
      }
      children.add(FadeTransition(
        opacity: opacity,
        child: item,
      ));
    }

    final CurveTween opacity =
        CurveTween(curve: const Interval(0.0, 1.0 / 3.0));
    final CurveTween width = CurveTween(curve: Interval(0.0, unit));
    final CurveTween height =
        CurveTween(curve: Interval(0.0, unit * route.items.length));

    final Widget child = ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: _kMenuMinWidth,
        maxWidth: _kMenuMaxWidth,
      ),
      child: IntrinsicWidth(
        stepWidth: _kMenuWidthStep,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: semanticLabel,
          child: SingleChildScrollView(
            controller: controller,
            padding:
                const EdgeInsets.symmetric(vertical: _kMenuVerticalPadding),
            child: ListBody(children: children),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: route.animation!,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: opacity.evaluate(route.animation!),
          child: Material(
            type: MaterialType.transparency,
            elevation: route.elevation,
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              widthFactor: width.evaluate(route.animation!),
              heightFactor: height.evaluate(route.animation!),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class _PopupMenuRouteLayout extends SingleChildLayoutDelegate {
  _PopupMenuRouteLayout(
      this.position, this.selectedItemOffset, this.textDirection);

  final RelativeRect position;
  final double selectedItemOffset;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest -
            const Offset(_kMenuScreenPadding * 2.0, _kMenuScreenPadding * 2.0)
        as Size);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double y;
    y = position.top +
        (size.height - position.top - position.bottom) / 2.0 -
        selectedItemOffset;

    double x;
    if (position.left > position.right) {
      x = size.width - position.right - childSize.width;
    } else if (position.left < position.right) {
      x = position.left;
    } else {
      switch (textDirection) {
        case TextDirection.rtl:
          x = size.width - position.right - childSize.width;
          break;
        case TextDirection.ltr:
          x = position.left;
          break;
      }
    }

    if (x < _kMenuScreenPadding) {
      x = _kMenuScreenPadding;
    } else if (x + childSize.width > size.width - _kMenuScreenPadding) {
      x = size.width - childSize.width - _kMenuScreenPadding;
    }
    if (y < _kMenuScreenPadding) {
      y = _kMenuScreenPadding;
    } else if (y + childSize.height > size.height - _kMenuScreenPadding) {
      y = size.height - childSize.height - _kMenuScreenPadding;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopupMenuRouteLayout oldDelegate) {
    return position != oldDelegate.position;
  }
}

class _PopupMenuRoute<T> extends PopupRoute<T> {
  _PopupMenuRoute({
    required this.position,
    required this.items,
    this.initialValue,
    this.elevation = 8,
    required this.theme,
    required this.barrierLabel,
    required this.semanticLabel,
  });

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final dynamic initialValue;
  final double elevation;
  final ThemeData theme;
  final String semanticLabel;

  @override
  Animation<double> createAnimation() {
    return CurvedAnimation(
      parent: super.createAnimation(),
      curve: Curves.linear,
      reverseCurve: const Interval(0.0, _kMenuCloseIntervalEnd),
    );
  }

  @override
  Duration get transitionDuration => _kMenuDuration;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  final String barrierLabel;

  ScrollController? scrollController;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    double selectedItemOffset = 0;
    double scrollItemOffset = 0;
    if (initialValue != null) {
      double y = _kMenuVerticalPadding;
      for (PopupMenuEntry<T> entry in items) {
        if (entry.represents(initialValue)) {
          selectedItemOffset = y + entry.height / 2.0;
          scrollItemOffset = y - entry.height / 2.0;
          break;
        }
        y += entry.height;
      }
    }
    scrollController = ScrollController(initialScrollOffset: scrollItemOffset);

    Widget menu = _PopupMenu<T>(
        route: this,
        semanticLabel: semanticLabel,
        controller: scrollController);
    menu = Theme(data: theme, child: menu);

    return SafeArea(
      child: Builder(
        builder: (BuildContext context) {
          return CustomSingleChildLayout(
            delegate: _PopupMenuRouteLayout(
              position,
              selectedItemOffset,
              Directionality.of(context),
            ),
            child: menu,
          );
        },
      ),
    );
  }
}

Future<T?> showMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double elevation = 8.0,
  String semanticLabel = "",
}) {
  assert(items.isNotEmpty);
  assert(debugCheckHasMaterialLocalizations(context));
  String label = semanticLabel;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      label = semanticLabel;
      break;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
      label = semanticLabel.isNotEmpty
          ? semanticLabel
          : MaterialLocalizations.of(context).popupMenuLabel;
      break;
    default:
      label = semanticLabel;
  }

  return Navigator.push(
      context,
      _PopupMenuRoute<T>(
        position: position,
        items: items,
        initialValue: initialValue,
        elevation: elevation,
        semanticLabel: label,
        theme: Theme.of(context),
        barrierLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
      ));
}

typedef PopupMenuItemSelected<T> = void Function(T value);
typedef PopupMenuCanceled = void Function();
typedef PopupMenuItemBuilder<T> = List<PopupMenuEntry<T>> Function(
    BuildContext context);

class PopupMenuButton<T> extends StatelessWidget {
  const PopupMenuButton({
    Key? key,
    required this.itemBuilder,
    this.initialValue,
    this.onSelected,
    this.onCanceled,
    this.tooltip,
    this.elevation = 8.0,
    this.padding = const EdgeInsets.all(8.0),
    this.child,
    this.icon,
    this.offset = Offset.zero,
    this.enabled = true,
  })  : assert(!(child != null &&
            icon != null)), 
        super(key: key);

  final PopupMenuItemBuilder<T> itemBuilder;
  final T? initialValue;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final double elevation;
  final EdgeInsetsGeometry padding;
  final Widget? child;
  final Icon? icon;
  final Offset offset;
  final bool enabled;

  void showButtonMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(offset, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final List<PopupMenuEntry<T>> items = itemBuilder(context);
    
    if (items.isNotEmpty) {
      showMenu<T>(
        context: context,
        elevation: elevation,
        items: items,
        initialValue: initialValue,
        position: position,
      ).then<void>((T? newValue) {
        if (newValue == null) {
          onCanceled?.call();
          return null;
        }
        onSelected?.call(newValue);
      });
    }
  }

  Icon _getIcon(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return const Icon(Icons.more_vert);
      case TargetPlatform.iOS:
        return const Icon(Icons.more_horiz);
      default:
        return const Icon(Icons.more_vert);
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterialLocalizations(context));

    return child != null
        ? InkWell(
            onTap: enabled ? () => showButtonMenu(context) : null,
            child: child,
          )
        : IconButton(
            icon: icon ?? _getIcon(Theme.of(context).platform),
            padding: padding,
            tooltip:
                tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
            onPressed: enabled ? () => showButtonMenu(context) : null,
          );
  }
}