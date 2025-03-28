local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local remote = ReplicatedStorage:WaitForChild("NotificarJogador")

remote.OnClientEvent:Connect(function(titulo, mensagem)
	-- Ignora se for "Ocultar"
	if titulo == "Ocultar" then return end

	-- Garante que o canal geral está disponível
	local success, canal = pcall(function()
		return TextChatService:WaitForChild("TextChannels"):WaitForChild("RBXGeneral")
	end)

	if success and canal then
		local msgFinal = "[" .. titulo .. "]: " .. mensagem
		canal:DisplaySystemMessage(msgFinal)
	else
		warn("Não foi possível acessar o canal de chat.")
	end
end)
