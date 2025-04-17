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

	local somDigitacao = Instance.new("Sound")
	somDigitacao.Name = "SomDigitacao"
	somDigitacao.SoundId = "rbxassetid://6895079853"
	somDigitacao.Volume = 0.2
	somDigitacao.Looped = true
	somDigitacao.Parent = ReplicatedStorage
end

criarSons()

-- sem isso nao roda preciso do ngrok ~sempre lembrar~
local PERGUNTA_URL = "https://3ba3-179-153-34-87.ngrok-free.app/pergunta"
local RESPOSTA_URL = "https://3ba3-179-153-34-87.ngrok-free.app/resposta"
local DICA_URL = "https://3ba3-179-153-34-87.ngrok-free.app/dica"

-- Tabelas
local perguntasAtuais = {}
local jogadorEmEspera = {}
local debitos = {}
local debitosAjuda = {}
local debitosErro = {}
local debitosPulo = {}
local respostasTemporarias = {} -- Armazena respostas aguardando confirmação
local jogadorEsperandoConfirmacao = {} -- Jogadores esperando confirmação
local jogadorTerminouIntroducao = {} -- Controle de jogadores que terminaram a introdução

-- Função para simular digitação gradual
local function animarTexto(textLabel, texto, velocidade, somDigitacao)
	textLabel.Text = ""

	if somDigitacao then
		somDigitacao:Play()
	end

	for i = 1, #texto do
		textLabel.Text = string.sub(texto, 1, i)

		-- Ajustar a velocidade com base no caractere (pausa maior em pontuações)
		local char = string.sub(texto, i, i)
		local espera = velocidade

		if char == "." or char == "!" or char == "?" then
			espera = velocidade * 5
		elseif char == "," or char == ";" or char == ":" then
			espera = velocidade * 3
		elseif char == "\n" then
			espera = velocidade * 8
		end

		wait(espera)
	end

	if somDigitacao then
		somDigitacao:Stop()
	end
end

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

-- Função para exibir as estatísticas finais de forma organizada
local function exibirEstatisticasFinais(player, acertos, erros, ajudas, pulos, totalGanho, gastoErro, gastoAjuda, gastoPulo, saldoFinal)
	-- Início do relatório
	remote:FireClient(player, "Resultado", "🏁 FIM DA PARTIDA! 🏁")
	task.wait(2)

	-- Resumo de desempenho
	local resumoDesempenho = string.format(
		"📊 RESUMO FINAL 📊\n" ..
			"✅ Acertos: %d | ❌ Erros: %d\n" ..
			"💡 Dicas: %d | 🔁 Pulos: %d",
		acertos, erros, ajudas, pulos
	)
	remote:FireClient(player, "Resultado", resumoDesempenho)
	task.wait(3)

	-- Resumo financeiro
	local resumoFinanceiro = string.format(
		"💰 BALANÇO FINANCEIRO 💰\n" ..
			"➕ Total ganho: R$ %d\n" ..
			"➖ Total gasto: R$ %d\n" ..
			"   ├─ Erros: R$ %d\n" ..
			"   ├─ Dicas: R$ %d\n" ..
			"   └─ Pulos: R$ %d",
		totalGanho, (gastoErro + gastoAjuda + gastoPulo), gastoErro, gastoAjuda, gastoPulo
	)
	remote:FireClient(player, "Resultado", resumoFinanceiro)
	task.wait(3)

	-- Resultado final
	local resultadoFinal = string.format("💵 SALDO FINAL: R$ %d 💵", saldoFinal)
	remote:FireClient(player, "Resultado", resultadoFinal)
end

-- pergunta do servidor
local function enviarPergunta(player)
	-- Verificar se o jogador terminou a introdução antes de enviar a pergunta
	if not jogadorTerminouIntroducao[player.UserId] then
		return
	end

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

-- Função para verificar resposta com o servidor
local function verificarResposta(player, mensagem)
	-- Verificar se o jogador terminou a introdução
	if not jogadorTerminouIntroducao[player.UserId] then
		return
	end

	if jogadorEmEspera[player.UserId] then
		remote:FireClient(player, "Resultado", "⏳ Já estamos processando algo, aguarde.")
		return
	end

	jogadorEmEspera[player.UserId] = true
	remote:FireClient(player, "Resultado", "⏳ ChatGPT está analisando sua resposta...")

	local pergunta = perguntasAtuais[player.UserId]
	local dados = { id = pergunta.id, resposta = mensagem }
	local success, respostaServer = pcall(function()
		return HttpService:PostAsync(
			RESPOSTA_URL,
			HttpService:JSONEncode(dados),
			Enum.HttpContentType.ApplicationJson
		)
	end)

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
			if respondidas >= 5 then
				-- Estatísticas finais reais
				local acertos = player:GetAttribute("Acertos")
				local erros = player:GetAttribute("Erros")
				local ajudas = player:GetAttribute("Ajuda")
				local pulos = player:GetAttribute("Pulos")
				local recompensaMedia = math.floor((player:GetAttribute("Dinheiro") + (debitos[player.UserId] or 0)) / math.max(acertos, 1))
				local totalGanho = acertos * recompensaMedia

				local gastoErro = debitosErro[player.UserId] or 0
				local gastoAjuda = debitosAjuda[player.UserId] or 0
				local gastoPulo = debitosPulo[player.UserId] or 0
				local totalGasto = gastoErro + gastoAjuda + gastoPulo

				local saldoFinal = math.max(0, totalGanho - totalGasto)

				-- Exibir estatísticas de forma organizada usando a nova função
				exibirEstatisticasFinais(player, acertos, erros, ajudas, pulos, totalGanho, gastoErro, gastoAjuda, gastoPulo, saldoFinal)
			else
				enviarPergunta(player)
			end
		else
			player:SetAttribute("Erros", player:GetAttribute("Erros") + 1)
			local valorDebitoErro = math.random(20000, 100000)
			local novoSaldo = math.max(0, player:GetAttribute("Dinheiro") - valorDebitoErro)
			debitos[player.UserId] = (debitos[player.UserId] or 0) + valorDebitoErro
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
end

-- Função para criar a introdução do jogo com efeito de digitação
local function criarIntroducaoParaJogador(player)
	-- Criar GUI para mensagens de introdução
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "IntroducaoGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player:WaitForChild("PlayerGui")

	-- Fundo preto para tela inteira
	local fundoPreto = Instance.new("Frame")
	fundoPreto.Name = "FundoPreto"
	fundoPreto.Size = UDim2.new(1, 0, 1, 0)
	fundoPreto.BackgroundColor3 = Color3.new(0, 0, 0)
	fundoPreto.BackgroundTransparency = 0
	fundoPreto.ZIndex = 5
	fundoPreto.Parent = screenGui

	-- Texto para exibir as mensagens
	local mensagemTexto = Instance.new("TextLabel")
	mensagemTexto.Name = "MensagemTexto"
	mensagemTexto.Size = UDim2.new(0.9, 0, 0.8, 0)
	mensagemTexto.Position = UDim2.new(0.05, 0, 0.1, 0)
	mensagemTexto.BackgroundTransparency = 1
	mensagemTexto.Font = Enum.Font.GothamBold
	mensagemTexto.TextColor3 = Color3.new(1, 1, 1)
	mensagemTexto.TextSize = 36
	mensagemTexto.TextWrapped = true
	mensagemTexto.TextYAlignment = Enum.TextYAlignment.Center
	mensagemTexto.TextXAlignment = Enum.TextXAlignment.Center
	mensagemTexto.TextStrokeTransparency = 0.5
	mensagemTexto.TextStrokeColor3 = Color3.new(0, 0, 0)
	mensagemTexto.ZIndex = 6
	mensagemTexto.Parent = fundoPreto

	-- Desativar controles do jogador durante a introdução
	local caractere = player.Character
	if caractere then
		local humanoid = caractere:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
		end
	end

	-- Som de digitação
	local somDigitacao = ReplicatedStorage:FindFirstChild("SomDigitacao"):Clone()
	somDigitacao.Parent = screenGui

	local mensagens = {
		{texto = "🩸💀 SEJA BEM-VINDO À ILHA DA ÚLTIMA RESPOSTA 💀🩸", cor = Color3.new(1, 0, 0)},
		{texto = "Este jogo foi inspirado no Show do Milhão, mas com alguns detalhes... levemente aprimorados", cor = Color3.new(1, 1, 1)},
		{texto = "💰 Quer ganhar dinheiro?\nAperte a tecla \";\" para abrir o chat e responder às perguntas.", cor = Color3.new(1, 0.8, 0)},
		{texto = "🎯 REGRAS SÃO SIMPLES:\n\nResponda certo. Ganhe grana.\nErrou? Vai pagar por isso.", cor = Color3.new(0, 1, 1)},
		{texto = "⚠️ PRESTE ATENÇÃO:\n\nCada erro, cada dica, cada pergunta pulada...\nDEBITA o seu saldo.\n\nSem choro. 😢", cor = Color3.new(1, 0.6, 0)},
		{texto = "🆘 PRECISA DE AJUDA?\n\nDigite \"ajuda!\"\n\nQUER PULAR?\n\nDigite \"pula!\"\n\nMas tudo aqui tem preço, campeão.", cor = Color3.new(0, 1, 0.6)},
		{texto = "⏳ O JOGO COMEÇA EM 5 SEGUNDOS...\n\n💀 BOA SORTE. VOCÊ VAI PRECISAR.", cor = Color3.new(1, 0, 0)}
	}

	-- Exibir cada mensagem com efeito de digitação
	for i, mensagem in ipairs(mensagens) do
		mensagemTexto.TextColor3 = mensagem.cor

		-- Som de nova mensagem (notificação)
		local somMensagem = Instance.new("Sound")
		somMensagem.SoundId = "rbxassetid://255881176"
		somMensagem.Volume = 0.3
		somMensagem.Parent = screenGui
		somMensagem:Play()
		game:GetService("Debris"):AddItem(somMensagem, 2)

		-- Efeito de digitação
		animarTexto(mensagemTexto, mensagem.texto, 0.03, somDigitacao)

		-- Esperar 3 segundos após terminar de digitar para dar tempo de ler
		wait(3)
	end

	-- Som de início
	local somInicio = Instance.new("Sound")
	somInicio.SoundId = "rbxassetid://1584273566"
	somInicio.Volume = 1
	somInicio.Parent = screenGui
	somInicio:Play()

	-- Contagem regressiva de 5 segundos (opcional)
	wait(3)
	screenGui:Destroy()

	-- Restaurar controles do jogador
	if caractere then
		local humanoid = caractere:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 16
			humanoid.JumpPower = 50
		end
	end

	-- Marcar que o jogador concluiu a introdução
	jogadorTerminouIntroducao[player.UserId] = true

	-- Iniciar o jogo enviando a primeira pergunta
	task.wait(1)
	enviarPergunta(player)
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
	debitosErro[player.UserId] = 0
	debitosAjuda[player.UserId] = 0
	debitosPulo[player.UserId] = 0
	jogadorEsperandoConfirmacao[player.UserId] = false
	jogadorTerminouIntroducao[player.UserId] = false -- Inicializa como falso

	HttpService:PostAsync("https://3ba3-179-153-34-87.ngrok-free.app/reiniciar",
		HttpService:JSONEncode({ jogadorId = tostring(player.UserId) }),
		Enum.HttpContentType.ApplicationJson
	)

	-- Iniciar sequência de introdução
	task.wait(3) -- Tempo para o jogador carregar completamente
	criarIntroducaoParaJogador(player)

	if not player:GetAttribute("ConectadoAoChat") then
		player:SetAttribute("ConectadoAoChat", true)

		player.Chatted:Connect(function(msg)
			-- Ignorar mensagens de chat se a introdução não terminou
			if not jogadorTerminouIntroducao[player.UserId] then
				return
			end

			local pergunta = perguntasAtuais[player.UserId]
			if not pergunta then return end

			if msg:lower() == "ajuda!" or msg:lower() == "help!" then
				if jogadorEmEspera[player.UserId] then
					remote:FireClient(player, "Resultado", "⏳ Já estamos processando algo, aguarde.")
					return
				end

				if jogadorEsperandoConfirmacao[player.UserId] then
					remote:FireClient(player, "Resultado", "⚠️ Você tem uma resposta pendente para confirmar. Digite 'sim!' para confirmar ou 'não!' para cancelar.")
					return
				end

				jogadorEmEspera[player.UserId] = true
				remote:FireClient(player, "Resultado", "💡 Gerando uma dica para te ajudar...")

				local success, respostaDica = pcall(function()
					return HttpService:GetAsync(DICA_URL)
				end)

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
					debitos[player.UserId] = (debitos[player.UserId] or 0) + valorDebitoAjuda
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
					remote:FireClient(player, "Resultado", "⏳ Já estamos processando algo, aguarde.")
					return
				end

				if jogadorEsperandoConfirmacao[player.UserId] then
					remote:FireClient(player, "Resultado", "⚠️ Você tem uma resposta pendente para confirmar. Digite 'sim!' para confirmar ou 'não!' para cancelar.")
					return
				end

				jogadorEmEspera[player.UserId] = true
				remote:FireClient(player, "Resultado", "🔁 Pulando a pergunta atual...")

				player:SetAttribute("Pulos", player:GetAttribute("Pulos") + 1)
				local valorDebito = math.random(0, 10000)
				local novoSaldo = math.max(0, player:GetAttribute("Dinheiro") - valorDebito)
				debitos[player.UserId] = (debitos[player.UserId] or 0) + valorDebito
				debitosPulo[player.UserId] = (debitosPulo[player.UserId] or 0) + valorDebito
				atualizarDinheiro(player, novoSaldo)

				task.wait(1)
				enviarPergunta(player)
				jogadorEmEspera[player.UserId] = false
				return
			end

			-- Processar confirmações
			if jogadorEsperandoConfirmacao[player.UserId] then
				if msg:lower() == "sim!" then
					jogadorEsperandoConfirmacao[player.UserId] = false
					verificarResposta(player, respostasTemporarias[player.UserId])
					return
				elseif msg:lower() == "não!" or msg:lower() == "nao!" then
					jogadorEsperandoConfirmacao[player.UserId] = false
					remote:FireClient(player, "Resultado", "🔄 Responda novamente à pergunta.")
					task.wait(1)
					local pergunta = perguntasAtuais[player.UserId]
					if pergunta then
						remote:FireClient(player, "Pergunta", pergunta.pergunta)
					end
					return
				else
					remote:FireClient(player, "Resultado", "⚠️ Você tem uma resposta pendente para confirmar. Digite 'sim!' para confirmar ou 'não!' para cancelar.")
					return
				end
			end

			-- Considera como resposta e pede confirmação
			if not jogadorEmEspera[player.UserId] and not jogadorEsperandoConfirmacao[player.UserId] then
				respostasTemporarias[player.UserId] = msg
				jogadorEsperandoConfirmacao[player.UserId] = true
				remote:FireClient(player, "Resultado", "🤔 Sua resposta é: \"" .. msg .. "\"\nTem certeza? Digite 'sim!' para confirmar ou 'não!' para responder novamente.")
			end
		end)
	end
end)

-- Configuração do cliente (remoto)
remote.OnServerEvent:Connect(function(player, tipo, conteudo)
	if tipo == "ConfirmarResposta" then
		-- Verificar se o jogador terminou a introdução
		if not jogadorTerminouIntroducao[player.UserId] then
			return
		end

		if conteudo:lower() == "sim" then
			verificarResposta(player, respostasTemporarias[player.UserId])
		else
			remote:FireClient(player, "Resultado", "🔄 Responda novamente à pergunta.")
			local pergunta = perguntasAtuais[player.UserId]
			if pergunta then
				task.wait(1)
				remote:FireClient(player, "Pergunta", pergunta.pergunta)
			end
		end 
	end
end)
