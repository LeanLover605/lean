--[[

	WebhookService - Send Discord webhooks with ease
	
	WebhookService allows developers to easily
	send Discord webhooks. It has support for embeds,
	proxies, rate-limiting, type-checking, etc
	
	Developed by Starnamics
	Licensed under the MIT License
	Version 1.0.0
	
	Supported Proxies:
		- hooks.hyra.io
	Other proxies have yet to of been tested
	
	If you discover any bugs, please report them in
	the DevForum post.
	
--]]

--// Types

export type EmbedData = {
	["title"]: string | nil,
	["description"]: string | nil,
	["url"]: string | nil,
	["timestamp"]: string | nil,
	["color"]: number | nil,
	["footer"]: {["text"]: string,["icon_url"]: string | nil} | nil,
	["author"]: {["name"]: string,["url"]: string | nil,["icon_url"]: string | nil} | nil,
	["fields"]: {{["name"]: string,["value"]: string,["inline"]: boolean | nil}?} | nil
}

export type WebhookData = {
	["content"]: string | nil,
	["username"]: string | nil,
	["avatar_url"]: string | nil,
	["tts"]: boolean | nil,
	["embeds"]: {[number]: EmbedData} | nil,
}

export type EmbedObject = {
	SetDescription: (EmbedObject,Description: string) -> EmbedObject,
	SetTitle: (EmbedObject,Title: string) -> EmbedObject,
	SetURL: (EmbedObject,URL: string) -> EmbedObject,
	SetTimestamp: (EmbedObject,Timestamp: string | nil) -> EmbedObject,
	SetColor: (EmbedObject,Color: Color3) -> EmbedObject,
	SetFooter: (EmbedObject,Text: string,Icon: string | nil) -> EmbedObject,
	SetAuthor: (EmbedObject,Name: string,URL: string | nil, Icon: string | nil) -> EmbedObject,
	AddField: (EmbedObject,Name: string,Value: string,Inline: boolean | nil) -> EmbedObject,
}

export type WebhookObject = {
	SetUsername: (WebhookObject,Username: string) -> WebhookObject,
	SetMessage: (WebhookObject,Message: string) -> WebhookObject,
	SetAvatar: (WebhookObject,Avatar: string) -> WebhookObject,
	SetTTS: (WebhookObject,TTS: boolean) -> WebhookObject,
	AddEmbed: (WebhookObject,Embed: EmbedObject) -> WebhookObject,
}

--// Module

local WebhookService = {}

local IsRequestRateLimited = false

--// Metatables

local Embed = {}
Embed.__index = Embed

local Webhook = {}
Webhook.__index = Webhook

--// Internal Functions

function ValidateWebhookObject(WebhookObject: WebhookObject)
	if WebhookObject["Data"]["content"] or WebhookObject["Data"]["embeds"] then return true end
end

function SendRequest(WebhookObject,WebhookUrl)
	if IsRequestRateLimited then repeat task.wait(1) until IsRequestRateLimited == false end
	local response = game:GetService("HttpService"):RequestAsync({
		Url = WebhookUrl,
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json"
		},
		Body = game:GetService("HttpService"):JSONEncode(WebhookObject["Data"])
	})

	if response.StatusCode == 404 then
		return {
			Success = false,
			Code = response.StatusCode,
			Message = "Webhook not found"
		}
	elseif response.StatusCode == 401 or response.StatusCode == 403 then
		return {
			Success = false,
			Code = response.StatusCode,
			Message = "Invalid webhook"
		}
	elseif response.StatusCode == 429 then
		local retry_after = response["Headers"]["ratelimit-reset"] or response["Headers"]["retry_after"]

		if not retry_after then
			return {
				Success = false,
				Code = response.StatusCode,
				Message = "Could not retry request"
			}
		end

		IsRequestRateLimited = true

		task.wait(retry_after)

		IsRequestRateLimited = false

		SendRequest(WebhookObject,WebhookUrl)
	elseif response.StatusCode == 200 then
		return {
			Success = true,
			Code = response.StatusCode,
			Message = "Webhook has been sent!"
		}
	end
end

--// Main Functions

function WebhookService:CreateEmbed(EmbedData: EmbedData | nil)
	local EmbedObject = {}
	EmbedObject["Data"] = EmbedData or {}
	setmetatable(EmbedObject,Embed)
	return EmbedObject
end

function WebhookService:CreateWebhook(WebhookData: WebhookData | nil)
	local WebhookObject = {}
	WebhookObject["Data"] = WebhookData or {}
	setmetatable(WebhookObject,Webhook)
	return WebhookObject
end

function WebhookService:SendAsync(WebhookObject: WebhookObject,WebhookUrl: string?)
	if not WebhookObject or not WebhookUrl then return false end
	if not ValidateWebhookObject(WebhookObject) then return false end

	local success, response = pcall(function()
		if IsRequestRateLimited then
			repeat task.wait(1) until IsRequestRateLimited == false
		end
		
		return SendRequest(WebhookObject,WebhookUrl)
	end)
	
	return response
end

--// Webhook Object Functions

function Webhook:SetMessage(Message: string)
	self["Data"]["content"] = Message
	return self :: WebhookObject
end

function Webhook:SetUsername(Username: string)
	self["Data"]["username"] = Username
	return self :: WebhookObject
end

function Webhook:SetAvatar(Avatar: string)
	self["Data"]["avatar_url"] = Avatar
	return self :: WebhookObject
end

function Webhook:SetTTS(TTS: boolean)
	self["Data"]["tts"] = TTS
	return self :: WebhookObject
end

function Webhook:AddEmbed(Embed: EmbedObject)
	if not self["Data"]["embeds"] then self["Data"]["embeds"] = {} end
	table.insert(self["Data"]["embeds"],Embed["Data"])
	return self :: WebhookObject
end

--// Embed Object Functions

function Embed:SetTitle(Title: string)
	self["Data"]["title"] = Title
	return self :: EmbedObject
end

function Embed:SetDescription(Description: string)
	self["Data"]["description"] = Description
	return self :: EmbedObject
end

function Embed:SetURL(URL: string)
	self["Data"]["url"] = URL
	return self :: EmbedObject
end

function Embed:SetTimestamp(Timestamp: string | nil)
	self["Data"]["timestamp"] = Timestamp or DateTime.now():ToIsoDate()
	return self :: EmbedObject
end

function Embed:SetColor(Color: Color3)
	self["Data"]["color"] = tonumber(Color:ToHex(),16)
	return self :: EmbedObject
end

function Embed:SetFooter(Text: string,Icon: string | nil)
	self["Data"]["footer"] = {["text"] = Text,["icon_url"] = Icon}
	return self :: EmbedObject
end

function Embed:SetAuthor(Name: string,URL: string | nil, Icon: string | nil)
	self["Data"]["author"] = {["name"] = Name,["url"] = URL, ["icon_url"] = Icon}
	return self
end

function Embed:AddField(Name: string,Value: string, Inline: boolean | nil)
	if not self["Data"]["fields"] then self["Data"]["fields"] = {} end
	table.insert(self["Data"]["fields"],{["name"] = Name,["value"] = Value,["inline"] = Inline})
	return self :: EmbedObject
end

return WebhookService
