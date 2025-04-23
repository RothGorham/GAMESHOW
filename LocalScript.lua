local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local remote = ReplicatedStorage:WaitForChild("NotificarJogador")

remote.OnClientEvent:Connect(function(tipo, mensagem, animado)
	-- Ignora se for "Ocultar"
	if tipo == "Ocultar" then return end

	-- Garante que o canal geral está disponível
	local success, canal = pcall(function()
		return TextChatService:WaitForChild("TextChannels"):WaitForChild("RBXGeneral")
	end)

	if success and canal then
		local mensagemFormatada = mensagem

		-- Formatação específica baseada no tipo
		if tipo == "Pergunta" then
			mensagemFormatada = "❓ " .. mensagem
		elseif tipo == "Resultado" then
			
		end

		canal:DisplaySystemMessage(mensagemFormatada)
	else
		warn("Não foi possível acessar o canal de chat.")
	end
end)

COLOCAR PERGUNTA E RESPOSTA NO CHAT, ASSIM FICA MEIO JOGADO!!! MUDAR ISSO!!!!!
