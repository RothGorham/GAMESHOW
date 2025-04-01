-- Serviços
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Comunicacao cliente-servidor
local remote = Instance.new("RemoteEvent")
remote.Name = "NotificarJogador"
remote.Parent = ReplicatedStorage

-- Sons no ReplicatedStorage
local function criarSons()
	local somMensagem = Instance.new("Sound")
	somMensagem.Name = "SomMensagem"
	somMensagem.SoundId = "rbxassetid://115672426899732"
	somMensagem.Volume = 0.5
	somMensagem.Parent = ReplicatedStorage

	local somAcerto = Instance.new("Sound")
	somAcerto.Name = "somAcerto"
	somAcerto.SoundId = "rbxassetid://109582532086060"
	somAcerto.Volume = 0.5
	somAcerto.Parent = ReplicatedStorage

	local somErro = Instance.new("Sound")
	somErro.Name = "SomErro"
	somErro.SoundId = "rbxassetid://124105429067328"
	somErro.Volume = 0.5
	somErro.Parent = ReplicatedStorage
end

criarSons()

-- sem isso nao roda preciso do ngrok ~sempre lembrar~
local PERGUNTA_URL = "https://5172-179-153-34-87.ngrok-free.app/pergunta"
local RESPOSTA_URL = "https://5172-179-153-34-87.ngrok-free.app/resposta"
local DICA_URL = "https://5172-179-153-34-87.ngrok-free.app/dica"

-- Tabelas
local perguntasAtuais = {}
local jogadorEmEspera = {}
local debitos = {}
local debitosAjuda = {}
local debitosErro = {}
local debitosPulo = {}

-- Atualizar dinheiro
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

-- pergunta do servidor
local function enviarPergunta(player)
	local success, response = pcall(function()
		return HttpService:GetAsync(PERGUNTA_URL)
	end)

	if success then
		local pergunta = HttpService:JSONDecode(response)
		perguntasAtuais[player.UserId] = pergunta
		player:SetAttribute("MensagemRecebida", "valorX")

		task.wait(0.5)

		remote:FireClient(player, "Pergunta", pergunta.pergunta)
	else
		warn("Erro ao buscar pergunta:", response)
		remote:FireClient(player, "Resultado", "❌ Erro ao buscar pergunta.")
	end
end


-- Quando jogador entra
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
	player:SetAttribute("Ajuda", 0)
	player:SetAttribute("MensagemRecebida", "")
	debitos[player.UserId] = 0

	HttpService:PostAsync("https://5172-179-153-34-87.ngrok-free.app/reiniciar",
		HttpService:JSONEncode({ jogadorId = tostring(player.UserId) }),
		Enum.HttpContentType.ApplicationJson
	)

	task.wait(1)
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
	
					local somOriginal = ReplicatedStorage:FindFirstChild("SomMensagem")
					if somOriginal then
						local somClone = somOriginal:Clone()
						somClone.Parent = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
						somClone:Play()
						game:GetService("Debris"):AddItem(somClone, 5)
					end

					task.wait(0.5) 

					local dica = HttpService:JSONDecode(respostaDica)
					remote:FireClient(player, "Resultado", "💬 Dica: " .. dica.dica)
					player:SetAttribute("Ajuda", player:GetAttribute("Ajuda") + 1)

					local valorDebitoAjuda = math.random(5000, 20000)
					local novoSaldo = math.max(0, player:GetAttribute("Dinheiro") - valorDebitoAjuda)
					debitos[player.UserId] += valorDebitoAjuda
					debitosAjuda[player.UserId] = (debitosAjuda[player.UserId] or 0) + valorDebitoAjuda
					atualizarDinheiro(player, novoSaldo)
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
				debitosPulo[player.UserId] = (debitosPulo[player.UserId] or 0) + valorDebito
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
					player:SetAttribute("MensagemRecebida", "acerto")
					task.wait(2)

					local respondidas = player:GetAttribute("PerguntasRespondidas")
					if respondidas >= 1 then
						-- Estatísticas finais reais
						local acertos = player:GetAttribute("Acertos")
						local recompensaMedia = math.floor((player:GetAttribute("Dinheiro") + (debitos[player.UserId] or 0)) / math.max(acertos, 1))
						local totalGanho = acertos * recompensaMedia

						local gastoErro = debitosErro[player.UserId] or 0
						local gastoAjuda = debitosAjuda[player.UserId] or 0
						local gastoPulo = debitosPulo[player.UserId] or 0
						local totalGasto = gastoErro + gastoAjuda + gastoPulo

						local saldoFinal = math.max(0, totalGanho - totalGasto)

						remote:FireClient(player, "Resultado", "🏁 Fim da partida!")
						task.wait(2)
						remote:FireClient(player, "", "########################")
						remote:FireClient(player, "Resultado", "✅ Perguntas corretas: " .. acertos)
						remote:FireClient(player, "Resultado", "💰 Total ganho: R$ " .. totalGanho)
						remote:FireClient(player, "Resultado", "💸 Total gasto:")
						remote:FireClient(player, "Resultado", " ❌ Erros: R$ " .. gastoErro)
						remote:FireClient(player, "Resultado", " 🆘 Ajuda: R$ " .. gastoAjuda)
						remote:FireClient(player, "Resultado", " 🔁 Pulos: R$ " .. gastoPulo)
						remote:FireClient(player, "", "########################")
						task.wait(2)
						remote:FireClient(player, "Resultado", "💵 Saldo final real: R$ " .. saldoFinal)
					else
						enviarPergunta(player)
					end

				else
					player:SetAttribute("Erros", player:GetAttribute("Erros") + 1)
					local valorDebitoErro = math.random(20000, 100000)
					local novoSaldo = math.max(0, player:GetAttribute("Dinheiro") - valorDebitoErro)
					debitos[player.UserId] += valorDebitoErro
					debitosErro[player.UserId] = (debitosErro[player.UserId] or 0) + valorDebitoErro
					atualizarDinheiro(player, novoSaldo)

					remote:FireClient(player, "Resultado", "❌ Resposta incorreta!")
					player:SetAttribute("MensagemRecebida", "erro")
					task.wait(2)

					-- Reenvia a mesma pergunta
					local pergunta = perguntasAtuais[player.UserId]
					if pergunta then
						remote:FireClient(player, "Pergunta", pergunta.pergunta)
					end
				end
			else
				warn("Erro ao consultar IA:", respostaServer)
				remote:FireClient(player, "Resultado", "❌ Erro ao verificar resposta.")
			end

			jogadorEmEspera[player.UserId] = false
		end)
	end
end)
