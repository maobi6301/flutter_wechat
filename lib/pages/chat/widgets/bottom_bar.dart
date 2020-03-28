import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_wechat/apis/apis.dart';
import 'package:flutter_wechat/global/global.dart';
import 'package:flutter_wechat/pages/chat/chat.dart';
import 'package:flutter_wechat/pages/chat/widgets/bottom_bar_tool_pane.dart';
import 'package:flutter_wechat/pages/chat/widgets/voice_button.dart';
import 'package:flutter_wechat/providers/chat/chat.dart';
import 'package:flutter_wechat/providers/chat/chat_list.dart';
import 'package:flutter_wechat/providers/chat_message/chat_message.dart';
import 'package:flutter_wechat/util/adapter/adapter.dart';
import 'package:flutter_wechat/util/style/style.dart';
import 'package:flutter_wechat/util/toast/toast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:common_utils/common_utils.dart';

class ChatBottomBar extends StatefulWidget {
  @override
  _ChatBottomBarState createState() => _ChatBottomBarState();
}

class _ChatBottomBarState extends State<ChatBottomBar> {
  TextEditingController _text = TextEditingController();

  bool _keyboard = true;
  bool _expand = false;

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [
      _buildLeftIcon(context),
      Expanded(child: _buildCenterChild(context)),
      _buildRightIcon(context),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Style.pBackgroundColor,
        border:
            Border(top: BorderSide(color: Style.pDividerColor, width: ew(1))),
      ),
      padding: EdgeInsets.symmetric(vertical: ew(10), horizontal: ew(10)),
      child: Column(
        children: <Widget>[
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: children),
          _buildToolPane(context),
        ],
      ),
    );
  }

  Widget _buildLeftIcon(BuildContext context) {
    return IconButton(
      icon: SvgPicture.asset(
        _keyboard
            ? 'assets/images/icons/voice-circle.svg'
            : 'assets/images/icons/keyboard.svg',
        color: Color(0xFF181818),
        width: ew(60),
      ),
      onPressed: () {
        _keyboard = !_keyboard;
        if (_expand) _expand = false;
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildCenterChild(BuildContext context) {
    if (_keyboard) {
      return TextField(
        controller: _text,
        minLines: 1,
        maxLines: 5,
        cursorColor: Style.pTintColor,
        style: TextStyle(fontSize: sp(32)),
        decoration: InputDecoration(
          fillColor: Colors.white,
          filled: true,
          contentPadding:
              EdgeInsets.symmetric(horizontal: ew(20), vertical: ew(10)),
          border: InputBorder.none,
        ),
        onTap: () {
          if (_expand) {
            _expand = false;
            if (mounted) setState(() {});
          }
          ChatPageState.of(context, listen: false)
              .toScrollEnd(delay: Future.delayed(Duration(milliseconds: 100)));
        },
        onChanged: (_) {
          if (_expand) _expand = false;
          if (mounted) setState(() {});
          ChatPageState.of(context, listen: false)
              .toScrollEnd(delay: Future.delayed(Duration(milliseconds: 100)));
        },
      );
    }
    return Container(
      height: ew(87),
      child: ChatVoiceButton(
        startRecord: () {
          if (_expand) {
            _expand = false;
            if (mounted) setState(() {});
          }
        },
        stopRecord: _sendVoice,
      ),
    );
  }

  Widget _buildRightIcon(BuildContext context) {
    return Visibility(
      visible: _text.text.isNotEmpty,
      child: Container(
        margin: EdgeInsets.only(left: ew(20), right: ew(10)),
        child: RaisedButton(
          elevation: 0,
          highlightElevation: 0,
          child: Text("发送"),
          color: Style.pTintColor,
          textColor: Colors.white,
          onPressed: () => _sendText(context),
        ),
      ),
      replacement: IconButton(
        icon: SvgPicture.asset('assets/images/icons/icons_outlined_add2.svg',
            color: Style.pTextColor, width: ew(60)),
        onPressed: () {
          _expand = !_expand;
          if (_expand)
            ChatPageState.of(context, listen: false).toScrollEnd(
                delay: Future.delayed(Duration(milliseconds: 100)));
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Widget _buildToolPane(BuildContext context) {
    return BottomBarToolPane(
      expand: _expand,
      onTap: (key) {
        if (key == "gallery")
          return _sendImage(context, source: ImageSource.gallery);

        if (key == "camera")
          return _sendImage(context, source: ImageSource.camera);
      },
    );
  }

  Future<ChatMessageProvider> _createSendMsg(
      {@required
          ChatMessageProvider Function(ChatMessageProvider message)
              updated}) async {
    var chat = ChatProvider.of(context, listen: false);
    var message = ChatMessageProvider(
      profileId: global.profile.profileId,
      sendId: global.uuid,
      sendTime: DateTime.now(),
      sourceId: chat.sourceId,
      fromFriendId: global.profile.friendId,
      fromNickname: global.profile.name,
      fromAvatar: global.profile.avatar,
      status: ChatMessageStatusEnum.sending,
    );

    if (chat.isContactChat) {
      message..toFriendId = chat.contact.friendId;
    }

    message = updated(message) ?? message;
    await chat.addMessage(message);
    ChatListProvider.of(context, listen: false).sort(forceUpdate: true);
    return message;
  }

  /// 发送文本消息
  _sendText(BuildContext context) async {
    if (_text.text.isEmpty) return;
    var message = await _createSendMsg(updated: (message) {
      return message
        ..type = MessageType.text
        ..body = _text.text;
    });
    _expand = false;
    ChatPageState.of(context, listen: false)
        .toScrollEnd(delay: Future.delayed(Duration(milliseconds: 100)));
    _text.text = "";
    if (mounted) setState(() {});

    // 发送消息
    var rsp = await toSendMessage(
        private: message.isPrivateMessage,
        sourceId: message.sourceId,
        type: message.type,
        body: message.body);
    if (!rsp.success) {
      Toast.showToast(context, message: rsp.message);
      message.status = ChatMessageStatusEnum.sendError;
      message.serialize(forceUpdate: true);
      if (mounted) setState(() {});
      return;
    }

    if (rsp.body != null && rsp.body is String && rsp.body.isNotEmpty)
      message.sendId = rsp.body as String;
    message.status = ChatMessageStatusEnum.complete;
    message.serialize(forceUpdate: true);
    if (mounted) setState(() {});
  }

  /// 发送语音
  _sendVoice(String path, double _seconds) async {
    LogUtil.v("语音路径：$path");
    LogUtil.v("语音时长：$_seconds");

    var seconds = _seconds.round();
    if (seconds == 0) return;

    var message = await _createSendMsg(updated: (message) {
      return message
        ..type = MessageType.urlVoice
        ..body = path + "?seconds=$seconds"
        ..bodyData = path + "?seconds=$seconds";
    });
    _expand = false;
    ChatPageState.of(context, listen: false)
        .toScrollEnd(delay: Future.delayed(Duration(milliseconds: 100)));
    if (mounted) setState(() {});

    // 上传附件
    var rsp = await toUploadFile(File(path),
        contentType: MediaType("audio", "wav"), suffix: "wav");
    if (!rsp.success) {
      Toast.showToast(context, message: rsp.message);
      message.status = ChatMessageStatusEnum.sendError;
      message.serialize(forceUpdate: true);
      if (mounted) setState(() {});
      return;
    }
    message.body = rsp.body;
    message.serialize(forceUpdate: true);
    if (mounted) setState(() {});

    // 发送消息
    rsp = await toSendMessage(
        private: message.isPrivateMessage,
        sourceId: message.sourceId,
        type: message.type,
        body: message.body);
    if (!rsp.success) {
      Toast.showToast(context, message: rsp.message);
      message.status = ChatMessageStatusEnum.sendError;
      message.serialize(forceUpdate: true);
      if (mounted) setState(() {});
      return;
    }

    if (rsp.body != null && rsp.body is String && rsp.body.isNotEmpty)
      message.sendId = rsp.body as String;
    message.status = ChatMessageStatusEnum.complete;
    message.serialize(forceUpdate: true);
    if (mounted) setState(() {});
  }

  /// 发送图片
  _sendImage(BuildContext context, {@required ImageSource source}) async {
    File image = await ImagePicker.pickImage(
        source: source ?? ImageSource.gallery,
        maxWidth: 750,
        maxHeight: 1334,
        imageQuality: 100);

    if (image == null) return;

    var message = await _createSendMsg(updated: (message) {
      return message
        ..type = MessageType.urlImg
        ..body = image.path
        ..bodyData = image.path;
    });
    _expand = false;
    ChatPageState.of(context, listen: false)
        .toScrollEnd(delay: Future.delayed(Duration(milliseconds: 100)));
    if (mounted) setState(() {});

    // 上传附件
    var rsp = await toUploadFile(image,
        contentType: MediaType("image", "png"), suffix: "png");
    if (!rsp.success) {
      Toast.showToast(context, message: rsp.message);
      message.status = ChatMessageStatusEnum.sendError;
      message.serialize(forceUpdate: true);
      if (mounted) setState(() {});
      return;
    }
    message.body = rsp.body;
    message.serialize(forceUpdate: true);
    if (mounted) setState(() {});

    // 发送消息
    rsp = await toSendMessage(
        private: message.isPrivateMessage,
        sourceId: message.sourceId,
        type: message.type,
        body: message.body);
    if (!rsp.success) {
      Toast.showToast(context, message: rsp.message);
      message.status = ChatMessageStatusEnum.sendError;
      message.serialize(forceUpdate: true);
      if (mounted) setState(() {});
      return;
    }

    if (rsp.body != null && rsp.body is String && rsp.body.isNotEmpty)
      message.sendId = rsp.body as String;
    message.status = ChatMessageStatusEnum.complete;
    message.serialize(forceUpdate: true);
    if (mounted) setState(() {});
  }
}
