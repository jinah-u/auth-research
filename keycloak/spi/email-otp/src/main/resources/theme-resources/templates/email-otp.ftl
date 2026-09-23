<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=true; section>
    <#if section = "header">
        이메일 인증 코드 입력
    <#elseif section = "form">
        <form id="kc-email-otp-form" action="${url.loginAction}" method="post">
            <p>등록된 메일로 보낸 6자리 코드를 입력하세요. (5분간 유효)</p>
            <input id="code" name="code" type="text" inputmode="numeric" autocomplete="one-time-code" autofocus />
            <input type="submit" value="확인" />
        </form>
    </#if>
</@layout.registrationLayout>
