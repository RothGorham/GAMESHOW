local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("NotificarJogador")

local PERGUNTA_URL = "https://1235-179-153-34-87.ngrok-free.app/pergunta"
local RESPOSTA_URL = "https://1235-179-153-34-87.ngrok-free.app/resposta"
local DICA_URL = "https://1235-179-153-34-87.ngrok-free.app/dica"

local perguntasAtuais = {}
local jogadorEmEspera = {}
local debitos = {}

local function atualizarDinheiro(player, novoValor)
	player:SetAttribute("Dinheiro", novoValor)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local dinheiroValor = leaderstats:FindFirstChild("Dinheiro")
		if dinheiroValor then
			dinheiroValor.Value = novoValor
		end
	end
end

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
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local dinheiro = Instance.new("IntValue")
	dinheiro.Name = "Dinheiro"
	dinheiro.Value = 0
	dinheiro.Parent = leaderstats

	player:SetAttribute("Dinheiro", 0)
	player:SetAttribute("PerguntasRespondidas", 0)
	player:SetAttribute("Acertos", 0)
	player:SetAttribute("Erros", 0)
	player:SetAttribute("Pulos", 0)
	debitos[player.UserId] = 0

	pcall(function()
		HttpService:PostAsync(
			"https://1235-179-153-34-87.ngrok-free.app/reiniciar",
			HttpService:JSONEncode({ jogadorId = tostring(player.UserId) }),
			Enum.HttpContentType.ApplicationJson
		)
	end)

	enviarPergunta(player)

	if not player:GetAttribute("ConectadoAoChat") then
		player:SetAttribute("ConectadoAoChat", true)

		player.Chatted:Connect(function(msg)
			local pergunta = perguntasAtuais[player.UserId]
			if not pergunta then return end

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

			if msg:lower() == "pular!" then
				if jogadorEmEspera[player.UserId] then
					remote:FireClient(player, "Aguardando", "⏳ Já estamos processando algo, aguarde.")
					return
				end

				jogadorEmEspera[player.UserId] = true
				remote:FireClient(player, "Resultado", "🔁 Pulando a pergunta atual...")

				player:SetAttribute("Pulos", player:GetAttribute("Pulos") + 1)
				local valorDebito = math.random(0, 10000)
				local novoSaldo = math.max(0, player:GetAttribute("Dinheiro") - valorDebito)
				debitos[player.UserId] += valorDebito
				atualizarDinheiro(player, novoSaldo)

				task.wait(1)
				enviarPergunta(player)
				jogadorEmEspera[player.UserId] = false
				return
			end

			if jogadorEmEspera[player.UserId] then
				remote:FireClient(player, "Aguardando", "⏳ Aguarde... analisando sua resposta.")
				return
			end

			jogadorEmEspera[player.UserId] = true
			remote:FireClient(player, "Aguardando", "⏳ ChatGPT está analisando sua resposta...")

			local dados = { id = pergunta.id, resposta = msg }

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
					local recompensa = math.random(10000, 50000)
					local total = player:GetAttribute("Dinheiro") + recompensa
					atualizarDinheiro(player, total)

					player:SetAttribute("PerguntasRespondidas", player:GetAttribute("PerguntasRespondidas") + 1)
					player:SetAttribute("Acertos", player:GetAttribute("Acertos") + 1)

					remote:FireClient(player, "Resultado", "✅ Resposta correta!")
					task.wait(2)

					local respondidas = player:GetAttribute("PerguntasRespondidas")
					if respondidas >= 50 then
						remote:FireClient(player, "Resultado", "🎉 Você ganhou R$ " .. total)
						task.wait(2)
						remote:FireClient(player, "Resultado", "📋 Estatísticas da partida:")
						remote:FireClient(player, "Resultado", "✅ Acertos: " .. player:GetAttribute("Acertos"))
						remote:FireClient(player, "Resultado", "❌ Erros: " .. player:GetAttribute("Erros"))
						remote:FireClient(player, "Resultado", "🔁 Pulos: " .. player:GetAttribute("Pulos"))
						task.wait(2)
						remote:FireClient(player, "Resultado", "🔍 Bom, vou analisar seus débitos...")
						task.wait(2)

						local totalDebitos = debitos[player.UserId] or 0
						if totalDebitos > 0 then
							local saldoFinal = math.max(0, total - totalDebitos)
							remote:FireClient(player, "Resultado", "💸 Você teve R$ " .. totalDebitos .. " em débitos.")
							task.wait(2)
							remote:FireClient(player, "Resultado", "📊 Seu saldo final é: R$ " .. saldoFinal)
						else
							remote:FireClient(player, "Resultado", "🌟 Realmente, você é um jogador diferenciado.")
						end
					else
						enviarPergunta(player)
					end
				else
					player:SetAttribute("Erros", player:GetAttribute("Erros") + 1)
					local valorDebitoErro = math.random(0, 10000)
					local novoSaldo = math.max(0, player:GetAttribute("Dinheiro") - valorDebitoErro)
					debitos[player.UserId] += valorDebitoErro
					atualizarDinheiro(player, novoSaldo)
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
