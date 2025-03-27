local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("NotificarJogador")

local PERGUNTA_URL = "https://94e4-177-73-181-130.ngrok-free.app/pergunta"
local RESPOSTA_URL = "https://94e4-177-73-181-130.ngrok-free.app/resposta"

local perguntasAtuais = {}
local jogadorEmEspera = {}

local function enviarPergunta(player)
	local success, response = pcall(function()
		return HttpService:GetAsync(PERGUNTA_URL)
	end)

	if success then
		local pergunta = HttpService:JSONDecode(response)
		perguntasAtuais[player.UserId] = pergunta
		remote:FireClient(player, "Pergunta", pergunta.pergunta)
	else
		warn("Erro ao buscar pergunta:", response)
		remote:FireClient(player, "Resultado", "❌ Erro ao buscar pergunta.")
	end
end

Players.PlayerAdded:Connect(function(player)
	enviarPergunta(player)

	if not player:GetAttribute("ConectadoAoChat") then
		player:SetAttribute("ConectadoAoChat", true)

		player.Chatted:Connect(function(msg)
			if jogadorEmEspera[player.UserId] then
				remote:FireClient(player, "Aguardando", "⏳ Aguarde... analisando sua resposta.")
				return
			end

			local pergunta = perguntasAtuais[player.UserId]
			if not pergunta then return end

			jogadorEmEspera[player.UserId] = true
			remote:FireClient(player, "Aguardando", "⏳ ChatGPT está analisando sua resposta...")

			local dados = {
				id = pergunta.id,
				resposta = msg
			}

			local success, respostaServer = pcall(function()
				return HttpService:PostAsync(
					RESPOSTA_URL,
					HttpService:JSONEncode(dados),
					Enum.HttpContentType.ApplicationJson
				)
			end)

			remote:FireClient(player, "Ocultar", "") -- oculta mensagem de "Aguardando"

			if success then
				local resultado = HttpService:JSONDecode(respostaServer)

				if resultado.correta then
					remote:FireClient(player, "Resultado", "✅ Resposta correta!")
					task.wait(2)
					enviarPergunta(player)
				else
					remote:FireClient(player, "Resultado", "❌ Resposta incorreta!")
					task.wait(2)
					remote:FireClient(player, "Pergunta", pergunta.pergunta)
				end
			else
				warn("Erro ao consultar IA:", respostaServer)
				remote:FireClient(player, "Resultado", "❌ Erro ao verificar resposta.")
			end

			jogadorEmEspera[player.UserId] = false
		end)
	end
end)
