-- Serviços
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- sem isso nao roda preciso do ngrok ~sempre lembrar~
local BASE_URL = "https://047f-179-153-34-87.ngrok-free.app"

-- Rotas específicas
local PERGUNTA_URL = BASE_URL .. "/pergunta"
local RESPOSTA_URL = BASE_URL .. "/resposta"
local DICA_URL = BASE_URL .. "/dica"
local REINICIAR_URL = BASE_URL .. "/reiniciar"

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

-- Função para salvar dados do jogador
local function SalvarDados(player, estatisticas)
	remote:FireClient(player, "Resultado", "📊 Você gostaria de salvar suas estatísticas? Digite 'sim!' ou 'nao!'")
	respostasTemporarias[player.UserId] = {
		estatisticas = {
			acertos = estatisticas.acertos,
			erros = estatisticas.erros,
			ajudas = estatisticas.ajudas,
			pulos = estatisticas.pulos,
			saldo = estatisticas.saldo
		},
		etapa = "confirmacao"
	}
	jogadorEsperandoConfirmacao[player.UserId] = true
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
	task.wait(2)

	-- Preparar estatísticas para salvar
	local estatisticas = {
		saldo = saldoFinal,
		acertos = acertos,
		erros = erros,
		ajudas = ajudas,
		pulos = pulos,
		totalGanho = totalGanho,
		gastoErro = gastoErro,
		gastoAjuda = gastoAjuda,
		gastoPulo = gastoPulo
	}

	-- Oferecer opção de salvar estatísticas
	SalvarDados(player, estatisticas)
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

		-- Primeiro toca o som
		local somOriginal = ReplicatedStorage:FindFirstChild("SomMensagem")
		if somOriginal then
			local somClone = somOriginal:Clone()
			somClone.Parent = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
			somClone:Play()
			game:GetService("Debris"):AddItem(somClone, 5)
		end

		-- Depois envia a pergunta para o chat
		remote:FireClient(player, "Pergunta", pergunta.pergunta)
		remote:FireClient(player, "Resultado", "❓ " .. pergunta.pergunta)
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
			if respondidas >= 1 then
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

-- Função revisada para criar a introdução do jogo com efeito de digitação
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
	mensagemTexto.Text = ""
	mensagemTexto.Parent = fundoPreto

	-- Som de tecla para o efeito de digitação
	local somTecla = Instance.new("Sound")
	somTecla.SoundId = "rbxassetid://4681278159" -- Som de tecla de máquina de escrever
	somTecla.Volume = 0.15
	somTecla.Parent = screenGui

	-- Desativar controles do jogador durante a introdução
	local caractere = player.Character
	if caractere then
		local humanoid = caractere:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
		end
	end

	local mensagens = {
		{texto = "🩸💀 SEJA BEM-VINDO À ILHA DA ÚLTIMA RESPOSTA 💀🩸", cor = Color3.new(1, 0, 0), velocidade = 0.03},
		{texto = "Este jogo foi inspirado no Show do Milhão, mas com alguns detalhes... levemente aprimorados", cor = Color3.new(1, 1, 1), velocidade = 0.04},
		{texto = "💰 Quer ganhar dinheiro?\nAperte a tecla \";\" para abrir o chat e responder às perguntas.", cor = Color3.new(1, 0.8, 0), velocidade = 0.04},
		{texto = "🎯 REGRAS SÃO SIMPLES:\n\nResponda certo. Ganhe grana.\nErrou? Vai pagar por isso.", cor = Color3.new(0, 1, 1), velocidade = 0.05},
		{texto = "⚠️ PRESTE ATENÇÃO:\n\nCada erro, cada dica, cada pergunta pulada...\nDEBITA o seu saldo.\n\nSem choro. 😢", cor = Color3.new(1, 0.6, 0), velocidade = 0.05},
		{texto = "🆘 PRECISA DE AJUDA?\n\nDigite \"ajuda!\"\n\nQUER PULAR?\n\nDigite \"pula!\"\n\nMas tudo aqui tem preço, campeão.", cor = Color3.new(0, 1, 0.6), velocidade = 0.04},
		{texto = "⏳ O JOGO COMEÇA EM 5 SEGUNDOS...\n\n💀 BOA SORTE. VOCÊ VAI PRECISAR.", cor = Color3.new(1, 0, 0), velocidade = 0.06}
	}

	-- Função que simula a digitação caractere por caractere
	local function simularDigitacao(texto, velocidade)
		mensagemTexto.Text = ""

		-- Dividir o texto em caracteres
		local chars = {}
		for c in texto:gmatch(".") do
			table.insert(chars, c)
		end

		-- Adicionar cada caractere com um pequeno atraso
		for i, char in ipairs(chars) do
			mensagemTexto.Text = mensagemTexto.Text .. char

			-- Tocar som de tecla para alguns caracteres (não para espaços ou a cada 3 caracteres para não sobrecarregar)
			if char ~= " " and i % 2 == 0 then
				somTecla:Play()
			end

			wait(velocidade) -- Velocidade de digitação
		end
	end

	-- Exibir cada mensagem com efeito de digitação
	for i, mensagem in ipairs(mensagens) do
		mensagemTexto.TextColor3 = mensagem.cor

		-- Som de nova mensagem
		local somMensagem = Instance.new("Sound")
		somMensagem.SoundId = "rbxassetid://255881176"
		somMensagem.Volume = 0.3
		somMensagem.Parent = screenGui
		somMensagem:Play()
		game:GetService("Debris"):AddItem(somMensagem, 2)

		-- Simular a digitação do texto
		simularDigitacao(mensagem.texto, mensagem.velocidade)

		-- Esperar um tempo após a mensagem ser completamente digitada
		local tempoEspera = 3 + (#mensagem.texto * 0.01) -- Tempo de espera proporcional ao tamanho da mensagem
		wait(tempoEspera)
	end

	-- Som de início
	local somInicio = Instance.new("Sound")
	somInicio.SoundId = "rbxassetid://1584273566"
	somInicio.Volume = 1
	somInicio.Parent = screenGui
	somInicio:Play()

	-- Remover GUI após a sequência
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

	HttpService:PostAsync(REINICIAR_URL,
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

			-- Processar confirmações de salvar dados
			if respostasTemporarias[player.UserId] then
				local dados = respostasTemporarias[player.UserId]

				if dados.etapa == "confirmacao" then
					if msg:lower() == "sim!" then
						remote:FireClient(player, "Resultado", "🔒 Digite o seu CPF (apenas números):")
						dados.etapa = "cpf"
					elseif msg:lower() == "nao!" then
						jogadorEsperandoConfirmacao[player.UserId] = false
						respostasTemporarias[player.UserId] = nil
						remote:FireClient(player, "Resultado", "😅 Então fica sem registro mesmo, gênio incompreendido!")
					else
						-- Adicionar esta parte para rejeitar respostas inválidas
						remote:FireClient(player, "Resultado", "⚠️ Por favor, responda apenas com 'sim!' ou 'nao!'")
					end
					return
				end

				if dados.etapa == "cpf" then
					-- Validar CPF (apenas números, 11 dígitos)
					if not msg:match("^%d+$") or #msg ~= 11 then
						remote:FireClient(player, "Resultado", "❌ CPF inválido! Digite apenas os 11 números do CPF.")
						return
					end
					dados.cpf = msg
					dados.etapa = "senha"
					remote:FireClient(player, "Resultado", "🔑 Agora digite a sua senha:")
					return
				end

				if dados.etapa == "senha" then
					local payload = HttpService:JSONEncode({
						cpf = dados.cpf,
						senha = msg,
						estatisticas = dados.estatisticas
					})

					local success, result = pcall(function()
						return HttpService:PostAsync(
							BASE_URL .. "/salvar-estatisticas",
							payload,
							Enum.HttpContentType.ApplicationJson
						)
					end)

					if success then
						local response = HttpService:JSONDecode(result)
						if response.ok then
							remote:FireClient(player, "Resultado", "✅ Estatísticas salvas com sucesso!")
						else
							remote:FireClient(player, "Resultado", "❌ " .. response.msg)
						end
					else
						remote:FireClient(player, "Resultado", "❌ Erro ao salvar estatísticas: " .. tostring(result))
					end

					jogadorEsperandoConfirmacao[player.UserId] = false
					respostasTemporarias[player.UserId] = nil
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
