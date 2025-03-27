local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("NotificarJogador")

local PERGUNTA_URL = "https://ef63-177-73-181-130.ngrok-free.app/pergunta"
local RESPOSTA_URL = "https://ef63-177-73-181-130.ngrok-free.app/resposta"
local DICA_URL = "https://ef63-177-73-181-130.ngrok-free.app/dica"

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
			local pergunta = perguntasAtuais[player.UserId]
			if not pergunta then return end

			-- 🧠 Comando de Dica (!dica)
			if msg:lower() == "ajuda!" or msg:lower() == "help!" then
				if jogadorEmEspera[player.UserId] then
					remote:FireClient(player, "Aguardando", "⏳ Já estamos processando algo, aguarde.")
					return
				end

				jogadorEmEspera[player.UserId] = true
				remote:FireClient(player, "Aguardando", "💡 Gerando uma dica para te ajudar...")

				local success, respostaDica = pcall(function()
					return HttpService:GetAsync(DICA_URL)
				end)

				remote:FireClient(player, "Ocultar", "")

				if success then
					local dica = HttpService:JSONDecode(respostaDica)
					remote:FireClient(player, "Resultado", "💬 Dica: " .. dica.dica)
				else
					warn("Erro ao obter dica:", respostaDica)
					remote:FireClient(player, "Resultado", "❌ Erro ao gerar dica.")
				end

				jogadorEmEspera[player.UserId] = false
				return
			end

			-- 🎯 Verificação de Resposta
			if jogadorEmEspera[player.UserId] then
				remote:FireClient(player, "Aguardando", "⏳ Aguarde... analisando sua resposta.")
				return
			end

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

			remote:FireClient(player, "Ocultar", "")

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
