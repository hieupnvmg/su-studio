// Optional: route text entry to AppKit's NSTextView when a Vietnamese input method misbehaves in WebKit.
// Off by default; users type straight into the form. Turn on in Cài đặt → Gõ tiếng Việt.
let nativeEditorField=null, nativeEditorSequence=0;
document.addEventListener('focusin',event=>{
 const field=event.target;
 if(!native||!state.typingPanel||nativeEditorField||!field.matches?.('textarea,input:not([type]),input[type=text],input[type=search]')||field.disabled||field.readOnly)return;
 nativeEditorField={field,requestId:String(++nativeEditorSequence)};
 field.blur();
 send('editText',{requestId:nativeEditorField.requestId,text:field.value,title:field.labels?.[0]?.textContent||field.closest('.field')?.querySelector('label')?.textContent||field.placeholder||'Soạn nội dung',multiline:field.tagName==='TEXTAREA'});
},true);
window.nativeTextEdited=function(result){
 const pending=nativeEditorField;
 if(!pending||pending.requestId!==result.requestId)return;
 nativeEditorField=null;
 if(result.accepted&&pending.field.isConnected){pending.field.value=result.text;pending.field.dispatchEvent(new Event('change',{bubbles:true}))}
};
