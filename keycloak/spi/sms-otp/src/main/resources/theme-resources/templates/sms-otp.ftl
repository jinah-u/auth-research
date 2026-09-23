<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=true; section>
    <#if section = "header">
        문자 인증번호 입력
    <#elseif section = "form">
        <form id="kc-sms-otp-form" action="${url.loginAction}" method="post">
            <p>${maskedPhone!""} 번호로 보낸 6자리 인증번호를 입력하세요. (5분간 유효)</p>
            <input id="code" name="code" type="text" inputmode="numeric" autocomplete="one-time-code" autofocus />
            <input type="submit" value="확인" />
        </form>
    </#if>
</@layout.registrationLayout>
