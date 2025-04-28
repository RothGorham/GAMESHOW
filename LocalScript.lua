local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local remote = ReplicatedStorage:WaitForChild("NotificarJogador")

-- Função para formatar a mensagem com base no tipo
local function formatarMensagem(tipo, mensagem)
	if tipo == "Pergunta" then
		return "❓ " .. mensagem
	elseif tipo == "Resultado" then
		return "->" .. mensagem
	else
		return mensagem
	end
end

-- Função para obter o canal de chat de forma segura
local function obterCanal()
	local success, canal = pcall(function()
		return TextChatService:WaitForChild("TextChannels"):WaitForChild("RBXGeneral")
	end)
	return success and canal or nil
end

-- Conexão do evento remoto
remote.OnClientEvent:Connect(function(tipo, mensagem, animado)
	if tipo == "Ocultar" then
		return
	end

	local canal = obterCanal()

	if canal then
		local mensagemFormatada = formatarMensagem(tipo, mensagem)
		canal:DisplaySystemMessage(mensagemFormatada)
	else
		warn("⚠️ Não foi possível acessar o canal de chat.")
	end
end)
